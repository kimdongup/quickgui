import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/model/operating_system.dart';
import 'package:quickgui/src/model/option.dart';
import 'package:quickgui/src/model/version.dart';
import 'package:quickgui/src/services/arm_media.dart';
import 'package:quickgui/src/services/download_session.dart';
import 'package:quickgui/src/services/guest_catalog.dart';

// Route requests to a real local HTTP server while retaining production URL checks.
class LocalClient implements HttpClient {
  LocalClient(this.server);
  final HttpServer server;
  final inner = HttpClient();
  final requested = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requested.add(url);
    return inner.getUrl(
      Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: url.path),
    );
  }

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final windows = MediaSource(
    kind: ArmMedia.windows,
    url: Uri.parse(
      'https://software.download.prss.microsoft.com/Win11_English_Arm64.iso?token=private',
    ),
    label: 'Windows ARM64',
  );
  final macos = MediaSource(
    kind: ArmMedia.macos,
    url: Uri.parse('https://updates.cdn-apple.com/UniversalMac_Restore.ipsw'),
    label: 'macOS ARM64',
  );
  final iso = Uint8List(40000)..setRange(32769, 32774, 'CD001'.codeUnits);
  final ipsw = Uint8List(1000)..setRange(0, 4, [80, 75, 3, 4]);

  test(
    'ARM choices are separate; x64 download overrides global ARM settings',
    () {
      final original = OperatingSystem('Windows', 'windows')
        ..versions.add(Version('11'));
      final items = withArmMedia([original, OperatingSystem('macOS', 'macos')]);
      expect(
        items.map((e) => e.displayName),
        containsAll([
          'Windows — x64',
          'Windows — ARM64',
          'macOS — Intel x64',
          'macOS — Apple Silicon ARM64',
        ]),
      );
      expect(original.versions.single.version, '11');
      expect(
        quickgetDownloadArguments(
          original,
          Version('11'),
          Option('Korean', 'curl'),
          ['--arch', 'arm64'],
        ),
        ['--arch', 'amd64', 'windows', '11', 'Korean'],
      );
      expect(
        quickgetDownloadArguments(
          OperatingSystem('Ubuntu', 'ubuntu'),
          Version('26.04'),
          null,
          ['--arch', 'arm64'],
        ),
        ['--arch', 'arm64', 'ubuntu', '26.04'],
      );
      expect(
        () => quickgetDownloadArguments(
          items.firstWhere((e) => e.armMedia != null),
          Version('11'),
          null,
          [],
        ),
        throwsArgumentError,
      );
    },
  );

  test('rejects x64, web pages, insecure and unofficial download URLs', () {
    for (final url in [
      'https://software.download.prss.microsoft.com/Win11_x64.iso',
      windowsArmPage,
      'http://software.download.prss.microsoft.com/Win11_Arm64.iso',
      'https://software.download.prss.microsoft.com.evil.example/Win11_Arm64.iso',
      'https://user:password@software.download.prss.microsoft.com/Win11_Arm64.iso',
      'https://software.download.prss.microsoft.com:8443/Win11_Arm64.iso',
    ]) {
      expect(
        () =>
            MediaSource(kind: ArmMedia.windows, url: Uri.parse(url), label: ''),
        throwsFormatException,
      );
    }
  });

  late Directory tmp;
  late HttpServer server;
  late LocalClient client;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('quickgui-media-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = LocalClient(server);
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });
  MediaDownloadSession session([MediaSource? source, LocalClient? transport]) =>
      MediaDownloadSession(
        source: source ?? windows,
        directory: tmp.path,
        clientFactory: () => transport ?? client,
      );
  Future<List<File>> files() async =>
      (await tmp.list(recursive: true).toList()).whereType<File>().toList();

  test(
    'streams complete ISO and IPSW into unique folders without overwriting',
    () async {
      server.listen((request) async {
        final body = request.uri.path.endsWith('.ipsw') ? ipsw : iso;
        request.response.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });
      final first = session();
      await first.start();
      expect(first.status, DownloadStatus.succeeded);
      expect(await File(first.savedPath!).readAsBytes(), iso);
      final second = session(windows, LocalClient(server));
      await second.start();
      expect(second.savedPath, isNot(first.savedPath));
      final apple = session(macos, LocalClient(server));
      await apple.start();
      expect(apple.status, DownloadStatus.succeeded);
      expect(await File(apple.savedPath!).readAsBytes(), ipsw);
      expect((await files()).length, 3);
      expect(
        (await files()).any(
          (f) => f.path.endsWith('.part') || f.path.endsWith('.conf'),
        ),
        isFalse,
      );
      first.dispose();
      second.dispose();
      apple.dispose();
    },
  );

  test(
    'follows a publisher redirect and rejects an unrelated redirect',
    () async {
      var bad = false;
      server.listen((request) async {
        if (request.uri.path.contains('English')) {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            bad
                ? 'https://untrusted.example/image.iso'
                : 'https://software.download.microsoft.com/Win11_Arm64.iso',
          );
        } else {
          request.response.add(iso);
        }
        await request.response.close();
      });
      final first = session();
      await first.start();
      expect(first.status, DownloadStatus.succeeded);
      expect(client.requested, hasLength(2));
      bad = true;
      final secondClient = LocalClient(server);
      final second = session(windows, secondClient);
      await second.start();
      expect(second.status, DownloadStatus.failed);
      expect(secondClient.requested, hasLength(1));
      first.dispose();
      second.dispose();
    },
  );

  for (final failure in ['http', 'html', 'fake', 'truncated']) {
    test('$failure response never becomes a completed image', () async {
      server.listen((request) async {
        try {
          if (failure == 'http') request.response.statusCode = 403;
          if (failure == 'html') {
            request.response.headers.contentType = ContentType.html;
          }
          if (failure == 'truncated') {
            request.response.contentLength = iso.length + 100;
            final socket = await request.response.detachSocket();
            socket.add(iso);
            await socket.close();
            return;
          }
          request.response.add('<html>error</html>'.codeUnits);
          await request.response.close();
        } catch (_) {
          /* Deliberately truncated response. */
        }
      });
      final download = session();
      await download.start().timeout(const Duration(seconds: 10));
      expect(download.status, DownloadStatus.failed);
      expect(download.savedPath, isNull);
      expect(download.error, isNot(contains('private')));
      expect(await files(), isEmpty);
      download.dispose();
    });
  }

  test(
    'cancel interrupts streaming and removes only its partial file',
    () async {
      final release = Completer<void>();
      server.listen((request) async {
        try {
          request.response.add(iso);
          await request.response.flush();
          await release.future;
          await request.response.close();
        } catch (_) {
          /* The client deliberately closed the connection. */
        }
      });
      final existing = File('${tmp.path}/keep.iso');
      await existing.writeAsString('existing image');
      final download = session();
      final done = download.start();
      while (download.received == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await download.cancel().timeout(const Duration(seconds: 5));
      release.complete();
      await done;
      expect(download.status, DownloadStatus.cancelled);
      expect(await existing.readAsString(), 'existing image');
      expect(await files(), hasLength(1));
      download.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test('cancel before start does not contact the server', () async {
    final download = session();
    await download.cancel();
    await download.start();
    expect(download.status, DownloadStatus.cancelled);
    expect(client.requested, isEmpty);
    download.dispose();
  });
}
