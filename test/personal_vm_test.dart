import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/download_result.dart';
import 'package:quickgui/src/services/download_session.dart';
import 'package:quickgui/src/services/vm_service.dart';

void main() {
  late Directory tmp;
  late File config;
  late VmOperations ops;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('quickgui-personal-test-');
    config = await File('${tmp.path}/a vm.conf').writeAsString(
      '# User comment\r\nguest_os="linux"\r\ndisk_img="a vm/disk.qcow2"\r\n',
    );
    ops = VmOperations();
  });
  tearDown(() async {
    ops.dispose();
    await tmp.delete(recursive: true);
  });
  test(
    'editing preserves comments, line endings and file permissions',
    () async {
      await Process.run('/bin/chmod', ['750', config.path]);
      final selected = (await ops.repository.inspect(config.path))!;
      final updated = '${selected.content}ram="4G"\r\n';
      await ops.saveConfig(selected, updated);
      expect(await config.readAsString(), updated);
      expect((await config.stat()).mode & 0x1ff, int.parse('750', radix: 8));
      expect(await tmp.list().length, 1);
      expect(ops.actionFor(config.path), isNull);
    },
  );
  test(
    'an external edit is preserved and a symlink cannot replace its target',
    () async {
      final selected = (await ops.repository.inspect(config.path))!;
      await config.writeAsString('${selected.content}# External change\n');
      await expectLater(
        ops.saveConfig(selected, 'lost data'),
        throwsStateError,
      );
      expect(await config.readAsString(), contains('# External change'));
      final link = await Link('${tmp.path}/alias.conf').create(config.path);
      final linked = (await ops.repository.inspect(link.path))!;
      await expectLater(ops.saveConfig(linked, 'lost data'), throwsStateError);
      expect(await Link(link.path).target(), config.path);
      expect(ops.actionFor(config.path), isNull);
    },
  );
  test('unknown or running VM state cannot be edited', () async {
    await Directory('${tmp.path}/a vm').create();
    await File('${tmp.path}/a vm/a vm.pid').writeAsString('$pid');
    final unknown = (await ops.repository.inspect(config.path))!;
    await expectLater(ops.saveConfig(unknown, 'lost data'), throwsStateError);
    expect(await config.readAsString(), unknown.content);
  });
  test('download success identifies the exact config and distinguishes existing VMs', () async {
    final before = await DownloadedVm.snapshot(tmp.path);
    final session = DownloadSession(
      executable: '/unused',
      arguments: [],
      directory: tmp.path,
      environment: {},
    );
    session.status = DownloadStatus.succeeded;
    session.log.add('    quickemu --vm a vm.conf\n');
    final existing = await DownloadedVm.fromSession(session, before);
    expect(existing!.path, config.path);
    expect(existing.isNew, isFalse);
    final created = await DownloadedVm.fromSession(session, {});
    expect(created!.isNew, isTrue);
    session.status = DownloadStatus.failed;
    expect(await DownloadedVm.fromSession(session, {}), isNull);
    session.status = DownloadStatus.cancelled;
    expect(await DownloadedVm.fromSession(session, {}), isNull);
    session.dispose();
  });
  test(
    'an unrelated recent config and an ambiguous log cannot select a VM',
    () async {
      final session = DownloadSession(
        executable: '/unused',
        arguments: [],
        directory: tmp.path,
        environment: {},
      );
      session.status = DownloadStatus.succeeded;
      session.log.add('100% Downloaded\n');
      expect(await DownloadedVm.fromSession(session, {}), isNull);
      session.log.add('quickemu --vm a vm.conf\nquickemu --vm other.conf\n');
      expect(await DownloadedVm.fromSession(session, {}), isNull);
      session.dispose();
    },
  );
}
