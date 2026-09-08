import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/vm_service.dart';
import 'package:quickgui/src/services/windows_installation.dart';

class RecordingRunner extends CommandRunner {
  Map<String, String>? environment;
  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
    Duration timeout = const Duration(seconds: 30),
    int outputLimit = 65536,
  }) async {
    this.environment = environment;
    return const CommandResult(1, '', 'Backend intentionally not started');
  }
}

void main() {
  test('Intel Windows profile preserves media, comments and disk; refuses shell logic and ARM', () {
    const original =
        '# Keep this\r\nguest_os="windows" # Windows 11 Pro\r\ndisk_img="windows/disk.qcow2"\r\niso="windows/install.iso"\r\nfixed_iso="windows/virtio.iso"\r\n';
    final profile = windowsIntelProfile(original, intelMac: true);
    expect(profile, startsWith('# Keep this\r\n'));
    expect(profile, contains('guest_os="windows-server" # Windows 11 Pro\r\n'));
    for (final key in ['disk_img', 'iso', 'fixed_iso']) {
      expect(configLiteral(profile, key), configLiteral(original, key));
    }
    expect(configLiteral(profile, 'extra_args'), contains('-cpu Nehalem'));
    expect(configLiteral(profile, 'extra_args'), contains('hpet=on'));
    expect(configLiteral(profile, 'tpm'), 'off');
    expect(windowsIntelProfile(profile, intelMac: true), profile);
    expect(
      () => windowsIntelProfile(original, intelMac: false),
      throwsStateError,
    );
    for (final extra in [
      'arch="aarch64"\n',
      'if true; then\n  iso="other.iso"\nfi\n',
      'extra_args="-snapshot"\n',
      'ram="4G"\nram="8G"\n',
      'ram="\$(echo 4G)"\n',
    ]) {
      expect(
        () => windowsIntelProfile('$original$extra', intelMac: true),
        throwsStateError,
      );
    }
  });

  test('installation marker blocks Run; confirmation archives only the marker and never invokes installer', () async {
    final tmp = await Directory.systemTemp.createTemp(
      'quickgui-windows-install-',
    );
    final runner = RecordingRunner();
    final ops = VmOperations(runner: runner);
    try {
      final state = await Directory('${tmp.path}/windows').create();
      final disk = await File('${state.path}/disk.qcow2')
          .writeAsString('existing user disk');
      final installer = await File('${state.path}/unattended.iso')
          .writeAsString('installation media');
      final marker = await File('${state.path}/installation-in-progress')
          .writeAsString('original marker');
      final file = await File('${tmp.path}/windows.conf').writeAsString(
        'guest_os="windows-server"\ndisk_img="windows/disk.qcow2"\niso=""\n',
      );
      final selected = (await ops.repository.inspect(file.path))!;
      expect(selected.installationPending, isTrue);
      Future<void> perform(VmRecord vm, VmAction action) => ops.perform(
        vm,
        action,
        executable: '/unused',
        environment: {'WINDOWS11_INSTALL': '1', 'PATH': '/usr/bin'},
      );
      await expectLater(perform(selected, VmAction.start), throwsStateError);
      expect(runner.environment, isNull);
      await perform(selected, VmAction.confirmInstallation);
      expect(runner.environment, isNull);
      expect(await marker.exists(), isFalse);
      final archives = await state.list().where((f) => f is Directory).toList();
      expect(archives, hasLength(1));
      expect(
        await File('${archives.single.path}/installation-in-progress')
            .readAsString(),
        'original marker',
      );
      expect(await disk.readAsString(), 'existing user disk');
      expect(await installer.readAsString(), 'installation media');
      expect(await file.readAsString(), selected.content);
      final completed = (await ops.repository.inspect(file.path))!;
      expect(completed.installationPending, isFalse);
      await expectLater(
        perform(completed, VmAction.start),
        throwsA(isA<ProcessException>()),
      );
      expect(runner.environment, {'PATH': '/usr/bin'});
      expect(ops.actionFor(file.path), isNull);
    } finally {
      ops.dispose();
      await tmp.delete(recursive: true);
    }
  });

  test('shared directory and symlink markers cannot be confirmed', () async {
    final tmp = await Directory.systemTemp.createTemp(
      'quickgui-shared-install-',
    );
    final ops = VmOperations();
    try {
      final state = await Directory('${tmp.path}/windows').create();
      final file = await File('${tmp.path}/a.conf')
          .writeAsString('guest_os="windows"\ndisk_img="windows/a.qcow2"\n');
      final other = await File('${tmp.path}/b.conf')
          .writeAsString('guest_os="windows"\ndisk_img="windows/b.qcow2"\n');
      final marker = await File('${state.path}/installation-in-progress')
          .writeAsString('keep');
      Future<void> confirm() async => ops.perform(
        (await ops.repository.inspect(file.path))!,
        VmAction.confirmInstallation,
        executable: '/unused',
        environment: {},
      );
      await expectLater(confirm(), throwsStateError);
      expect(await marker.readAsString(), 'keep');
      await other.delete();
      await marker.rename('${state.path}/original');
      await Link(marker.path).create('${state.path}/original');
      await expectLater(confirm(), throwsStateError);
      expect(await File('${state.path}/original').readAsString(), 'keep');
    } finally {
      ops.dispose();
      await tmp.delete(recursive: true);
    }
  });
}
