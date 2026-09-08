import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/connections.dart';
import 'package:quickgui/src/services/vm_service.dart';

class ControlledRepository extends VmRepository {
  late VmRecord record;
  @override
  Future<VmRecord?> inspect(String configPath) async => record;
}

class GateRunner extends CommandRunner {
  final entered = Completer<void>(), finish = Completer<void>();
  List<String>? arguments;
  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
    Duration timeout = const Duration(seconds: 30),
    int outputLimit = 65536,
  }) async {
    this.arguments = arguments;
    entered.complete();
    await finish.future;
    return const CommandResult(0, '', '');
  }
}

void main() {
  test(
    'mac defaults honor backend capabilities and explicit config values',
    () {
      expect(macStartArguments('', 'cocoa hda-output'), [
        '--display',
        'cocoa',
        '--sound-duplex',
        'hda-output',
      ]);
      expect(
        macStartArguments(
          'display="none"\nsound_duplex="hda-duplex"',
          'cocoa hda-output',
        ),
        isEmpty,
      );
      expect(macStartArguments('', 'legacy backend'), isEmpty);
    },
  );
  test('config parsing preserves literals and refuses shell evaluation', () {
    expect(
      configLiteral('disk_img="dir with spaces/한글.qcow2"\n', 'disk_img'),
      'dir with spaces/한글.qcow2',
    );
    expect(
      configLiteral("disk_img='literal\$disk.qcow2' # comment", 'disk_img'),
      'literal\$disk.qcow2',
    );
    expect(configLiteral('disk_img="\$(touch /tmp/no)"', 'disk_img'), isNull);
    expect(configLiteral('disk_img=a\ndisk_img=b', 'disk_img'), isNull);
    expect(configLiteral('disk_img=a; echo oops', 'disk_img'), isNull);
    expect(parsePort('-1'), isNull);
    expect(parsePort('65536'), isNull);
    expect(parsePort('22220'), 22220);
  });
  test(
    'uses disk_img directory and treats an unrelated live PID as unknown',
    () async {
      final tmp = await Directory.systemTemp.createTemp('quickgui-vms-');
      try {
        final config = File('${tmp.path}/my vm.conf');
        final disk = await Directory('${tmp.path}/other directory').create();
        await config.writeAsString(
          'guest_os="linux"\ndisk_img="other directory/disk.qcow2"\n',
        );
        await Directory('${tmp.path}/not-a-file.conf').create();
        final repo = const VmRepository();
        final stopped = (await repo.list(tmp.path)).single;
        expect(stopped.stateDirectory, disk.path);
        expect(stopped.state, VmState.stopped);
        await File('${disk.path}/my vm.pid').writeAsString('$pid');
        expect((await repo.inspect(config.path))!.state, VmState.unknown);
        await File('${disk.path}/my vm.pid').writeAsString('-1');
        expect((await repo.inspect(config.path))!.state, VmState.unknown);
      } finally {
        await tmp.delete(recursive: true);
      }
    },
  );
  test(
    'blocks deletion while starting, keeping spaced arguments intact',
    () async {
      final tmp = await Directory.systemTemp.createTemp('quickgui-actions-');
      final file = await File('${tmp.path}/my vm.conf')
          .writeAsString('fixture');
      final repo = ControlledRepository();
      repo.record = VmRecord(
        configPath: file.path,
        content: 'fixture',
        state: VmState.stopped,
      );
      final runner = GateRunner();
      final ops = VmOperations(repository: repo, runner: runner);
      try {
        final operation = ops.perform(
          repo.record,
          VmAction.start,
          executable: '/fake',
          environment: {},
        );
        await runner.entered.future;
        expect(ops.actionFor(file.path), VmAction.start);
        await expectLater(
          ops.perform(
            repo.record,
            VmAction.deleteDisk,
            executable: '/fake',
            environment: {},
          ),
          throwsStateError,
        );
        expect(runner.arguments, ['--vm', file.path]);
        repo.record = VmRecord(
          configPath: file.path,
          content: 'fixture',
          state: VmState.running,
        );
        runner.finish.complete();
        await operation;
        expect(ops.actionFor(file.path), isNull);
      } finally {
        ops.dispose();
        await tmp.delete(recursive: true);
      }
    },
  );
  test('rechecks a changed config after the confirmation dialog', () async {
    final tmp = await Directory.systemTemp.createTemp('quickgui-changed-');
    final file = await File('${tmp.path}/vm.conf').writeAsString('fixture');
    final repo = ControlledRepository();
    final selected = VmRecord(
      configPath: file.path,
      content: 'old',
      state: VmState.stopped,
    );
    repo.record = VmRecord(
      configPath: file.path,
      content: 'new',
      state: VmState.stopped,
    );
    final runner = GateRunner();
    final ops = VmOperations(repository: repo, runner: runner);
    try {
      await expectLater(
        ops.perform(
          selected,
          VmAction.deleteDisk,
          executable: '/fake',
          environment: {},
        ),
        throwsStateError,
      );
      expect(runner.arguments, isNull);
      expect(ops.actionFor(file.path), isNull);
    } finally {
      ops.dispose();
      await tmp.delete(recursive: true);
    }
  });
  test(
    'SSH arguments reject untrusted text and keep osascript one argument',
    () {
      expect(sshArguments('/usr/bin/xterm', 22220, 'user'), [
        '-e',
        'ssh',
        '-p',
        '22220',
        '-l',
        'user',
        'localhost',
      ]);
      expect(
        () => sshArguments('osascript', 22220, 'user; touch /tmp/file'),
        throwsFormatException,
      );
      expect(() => sshArguments('xterm', 0, 'user'), throwsFormatException);
      final args = sshArguments('osascript', 22220, 'user');
      expect(args.length, 2);
      expect(args.first, '-e');
      expect(args.last, contains('tell application "Terminal"'));
    },
  );
  test(
    'SSH detection handles split banners and times out a silent server',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final clients = <Socket>[];
      final subscription = server.listen((client) {
        clients.add(client);
        client.write('SS');
        Timer(const Duration(milliseconds: 20), () {
          client.write('H-2.0-test\r\n');
        });
      });
      expect(await detectSsh(server.port), isTrue);
      await subscription.cancel();
      await server.close();
      for (final client in clients) {
        client.destroy();
      }
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = silent.listen(clients.add);
      expect(
        await detectSsh(silent.port, timeout: const Duration(milliseconds: 60)),
        isFalse,
      );
      await accepted.cancel();
      await silent.close();
      for (final client in clients) {
        client.destroy();
      }
    },
  );
}
