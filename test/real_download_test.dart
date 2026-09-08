import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/download_result.dart';
import 'package:quickgui/src/services/download_session.dart';
import 'package:quickgui/src/services/toolchain.dart';

void main() {
  test(
    'public quickget downloads a small image and identifies its config',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'quickgui-real-download-',
      );
      final tools = Toolchain();
      final session = DownloadSession(
        executable: tools.find('quickget')!,
        arguments: ['tinycore', '15', 'CorePure64'],
        directory: directory.path,
        environment: tools.environment,
      );
      try {
        final before = await DownloadedVm.snapshot(directory.path);
        await session.start();
        expect(session.status, DownloadStatus.succeeded, reason: session.error);
        final created = await DownloadedVm.fromSession(session, before);
        expect(created, isNotNull);
        expect(created!.isNew, isTrue);
        expect(await File(created.path).exists(), isTrue);
        final images = await directory
            .list(recursive: true)
            .where((file) => file.path.endsWith('.iso'))
            .toList();
        expect(images, hasLength(1));
        expect(
          await File(images.single.path).length(),
          greaterThan(10 * 1024 * 1024),
        );
      } finally {
        if (!session.finished) {
          await session.cancel();
          await session.done;
        }
        session.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['QUICKGUI_REAL_DOWNLOAD_TESTS'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
