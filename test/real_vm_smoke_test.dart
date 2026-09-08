import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/vm_service.dart';
import 'package:quickgui/src/services/toolchain.dart';

/// Opt-in: uses only a new temporary disk. No existing VM is started or deleted.
void main() {
  test(
    'public Quickemu starts, stops and deletes a disposable VM',
    () async {
      final tools = Toolchain();
      final executable =
          Platform.environment['QUICKGUI_TEST_QUICKEMU'] ??
          tools.find('quickemu');
      expect(executable, isNotNull);
      final tmp = await Directory.systemTemp.createTemp('quickgui-real-vm-');
      final config = File('${tmp.path}/quickgui-smoke.conf');
      final ops = VmOperations();
      try {
        await config.writeAsString(
          'guest_os="linux"\nboot="legacy"\n'
          'disk_img="quickgui-smoke/disk.raw"\ndisk_format="raw"\ndisk_size="64M"\n'
          'ram="512M"\ncpu_cores="1"\nnetwork="none"\nsound_card="none"\n',
        );
        await Directory('${tmp.path}/quickgui-smoke').create();
        final disk = await File('${tmp.path}/quickgui-smoke/disk.raw')
            .open(mode: FileMode.write);
        await disk.truncate(64 * 1024 * 1024);
        await disk.close();
        final initial = (await ops.repository.inspect(config.path))!;
        await ops.perform(
          initial,
          VmAction.start,
          executable: executable!,
          environment: tools.environment,
          startArguments: [
            '--display',
            Platform.isMacOS ? 'cocoa' : 'none',
            '--viewer',
            'none',
          ],
        );
        final running = (await ops.repository.inspect(config.path))!;
        expect(running.state, VmState.running);
        await ops.perform(
          running,
          VmAction.stop,
          executable: executable,
          environment: tools.environment,
        );
        final stopped = (await ops.repository.inspect(config.path))!;
        expect(stopped.state, VmState.stopped);
        await ops.perform(
          stopped,
          VmAction.deleteDisk,
          executable: executable,
          environment: tools.environment,
        );
        expect(await config.exists(), isTrue);
        await ops.perform(
          stopped,
          VmAction.deleteVm,
          executable: executable,
          environment: tools.environment,
        );
        expect(await config.exists(), isFalse);
      } finally {
        if (await config.exists()) {
          final record = await ops.repository.inspect(config.path);
          if (record?.state == VmState.running) {
            await ops.perform(
              record!,
              VmAction.stop,
              executable: executable!,
              environment: tools.environment,
            );
          }
        }
        ops.dispose();
        await tmp.delete(recursive: true);
      }
    },
    skip: Platform.environment['QUICKGUI_REAL_VM_TESTS'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
