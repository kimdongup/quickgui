import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/model/operating_system.dart';
import 'package:quickgui/src/services/arm_media.dart';
import 'package:quickgui/src/services/download_session.dart';
import 'package:quickgui/src/services/vm_service.dart';
import 'package:quickgui/src/services/windows_x64_media.dart';
import 'package:quickgui/src/services/windows_x64_firmware.dart';

import 'arm_media_test.dart' show LocalClient;

Future<File> image(Directory root, String name, int size) async {
  final file = File('${root.path}/$name');
  final writer = await file.open(mode: FileMode.write);
  await writer.truncate(size); // Sparse fixture, not a real installation image.
  await writer.setPosition(32769);
  await writer.writeFrom('CD001'.codeUnits);
  await writer.close();
  return file;
}

void main() {
  late Directory root;
  late WindowsX64Firmware firmware;
  late Directory firmwareRoot;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('windows-x64-test-');
    firmwareRoot = await Directory.systemTemp.createTemp(
      'windows-firmware-test-',
    );
    firmware = WindowsX64Firmware(
      (await image(firmwareRoot, 'CODE.fd', 3653632)).path,
      (await image(firmwareRoot, 'VARS.fd', 540672)).path,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await firmwareRoot.delete(recursive: true);
  });

  test('rejects the known Quickemu EFI reset before installation', () async {
    final backend = File('${root.path}/quickemu');
    await backend.writeAsString(
      '    DISPLAY_RENDER=""\n    EFI_CODE=""\n    EFI_VARS=""',
    );
    await expectLater(
      validateWindowsFirmwareBackend(backend.path),
      throwsFormatException,
    );
    await backend.writeAsString(
      '    DISPLAY_RENDER=""\n    EFI_CODE="\u0024{EFI_CODE:-}"\n    EFI_VARS=""',
    );
    await validateWindowsFirmwareBackend(backend.path);
  });

  test(
    'Intel VM creation rejects absent firmware before creating files',
    () async {
      await expectLater(
        createWindowsX64Vm(
          directory: root.path,
          iso: 'missing.iso',
          intelProfile: true,
        ),
        throwsFormatException,
      );
      expect(await root.list().length, 0);
      await expectLater(
        const WindowsX64Firmware('/missing/code', '/missing/vars').validate(),
        throwsFormatException,
      );
    },
  );

  test(
    'rejects downloaded HTML and partial driver images without changing them',
    () async {
      final html = await File('${root.path}/virtio-win.iso')
          .writeAsString('<html>Not an ISO</html>');
      await expectLater(
        validateWindowsIso(html.path, driver: true),
        throwsFormatException,
      );
      expect(await html.readAsString(), '<html>Not an ISO</html>');
      final partial = await image(root, 'partial.iso', 40000);
      await expectLater(
        validateWindowsIso(partial.path, driver: true),
        throwsFormatException,
      );
    },
  );

  test('new manual VM preserves existing VM, uses Intel profile and no unattended image', () async {
    final previous = await File('${root.path}/windows-11-Korean.conf')
        .writeAsString('original config');
    final iso = await image(root, 'Win11_Korean_x64.iso', 1024 * 1024 * 1024);
    final driver = await image(root, 'virtio-win.iso', 32 * 1024 * 1024);
    final config = await createWindowsX64Vm(
      directory: root.path,
      iso: iso.path,
      driverIso: driver.path,
      intelProfile: true,
      firmware: firmware,
    );
    final content = await File(config).readAsString();
    expect(configLiteral(content, 'guest_os'), 'windows-server');
    expect(configLiteral(content, 'tpm'), 'on');
    expect(configLiteral(content, 'EFI_CODE'), firmware.code);
    expect(configLiteral(content, 'EFI_EXTRA_VARS'), firmware.variables);
    expect(configLiteral(content, 'iso'), iso.path);
    expect(configLiteral(content, 'fixed_iso'), driver.path);
    expect(configLiteral(content, 'extra_args'), contains('-cpu max'));
    expect(await File(configLiteral(content, 'disk_img')!).exists(), isFalse);
    expect(content, isNot(contains('unattended')));
    expect(await previous.readAsString(), 'original config');
    expect(await iso.length(), 1024 * 1024 * 1024);
    final second = await createWindowsX64Vm(
      directory: root.path,
      iso: iso.path,
      intelProfile: false,
    );
    expect(second, isNot(config));
    expect(
      configLiteral(await File(second).readAsString(), 'guest_os'),
      'windows',
    );
    expect(
      await root
          .list(recursive: true)
          .any((f) => f.path.endsWith('unattended.iso')),
      isFalse,
    );
  });

  test('invalid media cannot create a VM; ARM64 and shell metacharacters are rejected', () async {
    final iso = await image(root, 'Win11_arm64.iso', 1024 * 1024 * 1024);
    await expectLater(
      createWindowsX64Vm(
        directory: root.path,
        iso: iso.path,
        intelProfile: true,
        firmware: firmware,
      ),
      throwsFormatException,
    );
    final bad = await iso.rename('${root.path}/bad\u0024name.iso');
    await expectLater(
      createWindowsX64Vm(
        directory: root.path,
        iso: bad.path,
        intelProfile: true,
        firmware: firmware,
      ),
      throwsFormatException,
    );
    expect(await root.list().length, 1);
  });

  test(
    'x64 source rejects ARM links and driver downloader rejects HTTP 200 HTML',
    () async {
      expect(
        () => MediaSource(
          kind: ArmMedia.windows,
          windowsX64: true,
          url: Uri.parse(
            'https://software.download.prss.microsoft.com/Win11_arm64.iso',
          ),
          label: 'x64',
        ),
        throwsFormatException,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>challenge</html>');
        request.response.close();
      });
      final session = MediaDownloadSession(
        directory: root.path,
        source: MediaSource(
          kind: ArmMedia.windows,
          virtio: true,
          url: Uri.parse(virtioIsoUrl),
          label: 'drivers',
        ),
        clientFactory: () => LocalClient(server),
      );
      try {
        await session.start();
        expect(session.status, DownloadStatus.failed);
        expect(session.savedPath, isNull);
        expect(session.error, contains('web page'));
        expect(await root.list().length, 0);
      } finally {
        session.dispose();
        await server.close(force: true);
      }
    },
  );
}
