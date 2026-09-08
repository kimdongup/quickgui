import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/vm_service.dart';

class DeletionRunner extends CommandRunner {
  final calls = <List<String>>[];
  Future<void> Function(List<String>)? onCommand;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
    Duration timeout = const Duration(seconds: 30),
    int outputLimit = 65536,
  }) async {
    calls.add(arguments);
    if (onCommand == null) {
      return const CommandResult(1, '', 'Unexpected deletion command');
    }
    await onCommand!(arguments);
    return const CommandResult(0, '', '');
  }
}

Future<File> config(Directory root, String name, String disk) =>
    File('${root.path}/$name.conf')
        .writeAsString('guest_os="linux"\ndisk_img="$disk"\n');

Future<void> refuseDeletion(
  File selected,
  VmAction action,
  DeletionRunner runner,
) async {
  final repository = const VmRepository();
  final operations = VmOperations(repository: repository, runner: runner);
  try {
    await expectLater(
      operations.perform(
        (await repository.inspect(selected.path))!,
        action,
        executable: '/unused-backend',
        environment: {},
      ),
      throwsStateError,
    );
    expect(runner.calls, isEmpty, reason: 'Reject before invoking the backend');
    expect(operations.actionFor(selected.path), isNull);
  } finally {
    operations.dispose();
  }
}

void main() {
  test(
    'whole-VM deletion protects aliased and nested VM directories',
    () async {
      for (final alias in [true, false]) {
        final root = await Directory.systemTemp.createTemp(
          'quickgui-shared-dir-',
        );
        try {
          final own = await Directory('${root.path}/own').create();
          final disk = await File('${own.path}/disk.qcow2')
              .writeAsString('own');
          final nested = alias
              ? own
              : await Directory('${own.path}/nested').create();
          final peerDisk = await File('${nested.path}/peer.qcow2')
              .writeAsString('peer data');
          if (alias) await Link('${root.path}/alias').create(own.path);
          final selected = await config(root, 'selected', 'own/disk.qcow2');
          final peer = await config(
            root,
            'peer',
            alias ? 'alias/peer.qcow2' : 'own/nested/peer.qcow2',
          );
          await refuseDeletion(selected, VmAction.deleteVm, DeletionRunner());
          expect(await disk.readAsString(), 'own');
          expect(await peerDisk.readAsString(), 'peer data');
          expect(await peer.exists(), isTrue);
        } finally {
          await root.delete(recursive: true);
        }
      }
    },
  );

  test(
    'disk and VM deletion protect a disk referenced by another symlink',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'quickgui-shared-disk-',
      );
      try {
        final own = await Directory('${root.path}/own').create();
        final peer = await Directory('${root.path}/peer').create();
        final disk = await File('${own.path}/disk.qcow2')
            .writeAsString('shared data');
        await Link('${peer.path}/disk.qcow2').create(disk.path);
        final selected = await config(root, 'selected', 'own/disk.qcow2');
        await config(root, 'peer', 'peer/disk.qcow2');
        for (final action in [VmAction.deleteDisk, VmAction.deleteVm]) {
          await refuseDeletion(selected, action, DeletionRunner());
          expect(
            await File('${peer.path}/disk.qcow2').readAsString(),
            'shared data',
          );
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('independent VM storage can still be deleted', () async {
    final root = await Directory.systemTemp.createTemp('quickgui-independent-');
    final runner = DeletionRunner();
    final repository = const VmRepository();
    final operations = VmOperations(repository: repository, runner: runner);
    try {
      final own = await Directory('${root.path}/own').create();
      final peer = await Directory('${root.path}/peer').create();
      final disk = await File('${own.path}/disk.qcow2')
          .writeAsString('own data');
      final peerDisk = await File('${peer.path}/disk.qcow2')
          .writeAsString('peer data');
      final selected = await config(root, 'selected', 'own/disk.qcow2');
      final peerConfig = await config(root, 'peer', 'peer/disk.qcow2');
      runner.onCommand = (arguments) async {
        expect(arguments.take(2), ['--vm', selected.path]);
        if (arguments.last == '--delete-disk') {
          await disk.delete();
        } else {
          expect(arguments.last, '--delete-vm');
          await selected.delete();
          await own.delete(recursive: true);
        }
      };
      for (final action in [VmAction.deleteDisk, VmAction.deleteVm]) {
        await operations.perform(
          (await repository.inspect(selected.path))!,
          action,
          executable: '/unused-backend',
          environment: {},
        );
      }
      expect(runner.calls.length, 2);
      expect(await peerDisk.readAsString(), 'peer data');
      expect(await peerConfig.exists(), isTrue);
    } finally {
      operations.dispose();
      await root.delete(recursive: true);
    }
  });
}
