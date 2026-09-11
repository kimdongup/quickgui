import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../model/operating_system.dart';
import 'download_session.dart' show DownloadStatus;

const windowsArmPage =
    'https://www.microsoft.com/en-us/software-download/windows11arm64';

class MediaSource {
  MediaSource({
    required this.kind,
    required this.url,
    required this.label,
    this.windowsX64 = false,
    this.virtio = false,
  }) {
    validateUrl(url, kind, windowsX64: windowsX64, virtio: virtio);
  }
  final bool windowsX64, virtio;
  final ArmMedia kind;
  final Uri url;
  final String label;
  String get fileName => virtio
      ? 'virtio-win.iso'
      : windowsX64
      ? 'Windows-11-x64.iso'
      : kind == ArmMedia.windows
      ? 'Windows-11-ARM64.iso'
      : 'macOS-Apple-Silicon.ipsw';

  static void validateUrl(
    Uri url,
    ArmMedia kind, {
    bool checkName = true,
    bool windowsX64 = false,
    bool virtio = false,
  }) {
    if ((windowsX64 || virtio) && kind != ArmMedia.windows ||
        (windowsX64 && virtio)) {
      throw const FormatException('Invalid media selection.');
    }
    final host = url.host.toLowerCase();
    final official = virtio
        ? host == 'fedorapeople.org' &&
              url.path.startsWith('/groups/virt/virtio-win/direct-downloads/')
        : kind == ArmMedia.windows
        ? const [
            'software.download.prss.microsoft.com',
            'software.download.microsoft.com',
            'software-download.microsoft.com',
          ].contains(host)
        : host.endsWith('.cdn-apple.com') || host.endsWith('.apple.com');
    if (url.scheme != 'https' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.fragment.isNotEmpty ||
        !official) {
      throw const FormatException(
        'Use an HTTPS download link from the official publisher.',
      );
    }
    if (!checkName) return;
    final name = url.pathSegments.lastOrNull?.toLowerCase() ?? '';
    if (kind == ArmMedia.windows &&
        (!name.endsWith('.iso') ||
            (!virtio &&
                (windowsX64
                    ? !name.contains('x64') || name.contains('arm64')
                    : !name.contains('arm64'))))) {
      throw FormatException(
        windowsX64 || virtio
            ? 'Paste the official ISO download link for the selected architecture, not a web page.'
            : 'Paste the Windows 11 ARM64 ISO download link, not the web page or an x64 ISO.',
      );
    }
    if (kind == ArmMedia.macos && !name.endsWith('.ipsw')) {
      throw const FormatException(
        'The Apple download must be an IPSW restore image.',
      );
    }
  }
}

Future<MediaSource> latestMacRestoreImage() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'Finding a compatible macOS image requires an Apple Silicon Mac.',
    );
  }
  final data = await const MethodChannel('quickgui/restore-image')
      .invokeMapMethod<String, dynamic>('latestSupported')
      .timeout(const Duration(seconds: 60));
  if (data == null) throw StateError('Apple did not return a restore image.');
  return MediaSource(
    kind: ArmMedia.macos,
    url: Uri.parse(data['url'] as String),
    label: 'macOS ${data['version']} (${data['build']}) — Apple Silicon ARM64',
  );
}

/// Streams official installation media into a fresh directory in the workspace.
/// Existing images are never overwritten; only a complete image gets its final name.
class MediaDownloadSession extends ChangeNotifier {
  MediaDownloadSession({
    required this.source,
    required this.directory,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final MediaSource source;
  final String directory;
  final HttpClient Function() _clientFactory;
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  DownloadStatus status = DownloadStatus.starting;
  int received = 0;
  int? total;
  String? savedPath, error;
  HttpClient? _client;
  bool _cancelled = false, _started = false, _disposed = false;
  double? get progress =>
      total != null && total! > 0 ? (received / total!).clamp(0, 1) : null;
  bool get finished => [
    DownloadStatus.succeeded,
    DownloadStatus.failed,
    DownloadStatus.cancelled,
  ].contains(status);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<HttpClientResponse> _response() async {
    var url = source.url;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (_cancelled) throw const HttpException('Cancelled');
      MediaSource.validateUrl(
        url,
        source.kind,
        checkName: false,
        windowsX64: source.windowsX64,
        virtio: source.virtio,
      );
      final request = await _client!
          .getUrl(url)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        // Do not download a redirect body or follow it before validating its host.
        await response.listen((_) {}).cancel();
        if (location == null) {
          throw const FormatException('Download redirect has no location.');
        }
        url = url.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException(
          'Download returned HTTP ${response.statusCode}. Get a fresh link and retry.',
        );
      }
      return response;
    }
    throw const FormatException('Too many download redirects.');
  }

  Future<void> start() async {
    if (_started) throw StateError('Download already started');
    _started = true;
    Directory? target;
    File? partial;
    RandomAccessFile? writer;
    try {
      if (_cancelled) return;
      if (!await Directory(directory).exists()) {
        throw const FormatException(
          'The selected workspace is no longer available.',
        );
      }
      _client = _clientFactory()
        ..connectionTimeout = const Duration(seconds: 30);
      final response = await _response();
      if (_cancelled) return;
      if (response.headers.contentType?.mimeType.contains('html') ?? false) {
        throw const FormatException(
          'The server returned a web page instead of installation media.',
        );
      }
      total = response.contentLength >= 0 ? response.contentLength : null;
      final root = Directory(p.join(directory, 'Install Media'));
      await root.create(recursive: true);
      target = await root.createTemp(
        source.virtio
            ? 'virtio-'
            : source.windowsX64
            ? 'windows-x64-'
            : source.kind == ArmMedia.windows
            ? 'windows-arm64-'
            : 'macos-arm64-',
      );
      partial = File(p.join(target.path, '${source.fileName}.part'));
      writer = await partial.open(mode: FileMode.writeOnly);
      status = DownloadStatus.running;
      _changed();
      final header = <int>[];
      var lastUpdate = DateTime.now();
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        if (_cancelled) break;
        if (header.length < 32774) {
          header.addAll(chunk.take(32774 - header.length));
        }
        await writer.writeFrom(chunk);
        received += chunk.length;
        if (DateTime.now().difference(lastUpdate).inMilliseconds >= 100) {
          lastUpdate = DateTime.now();
          _changed();
        }
      }
      await writer.close();
      writer = null;
      if (_cancelled) return;
      if (received == 0 || (total != null && received != total)) {
        throw const FormatException('The image download is incomplete.');
      }
      final isImage = source.kind == ArmMedia.macos
          ? header.length >= 4 &&
                listEquals(header.take(4).toList(), [80, 75, 3, 4])
          : header.length >= 32774 &&
                [
                  'CD001',
                  'BEA01',
                  'NSR02',
                  'NSR03',
                ].contains(String.fromCharCodes(header.sublist(32769, 32774)));
      if ((source.windowsX64 && received < 1024 * 1024 * 1024) ||
          (source.virtio && received < 32 * 1024 * 1024)) {
        throw const FormatException(
          'The ISO is too small or incomplete. Use a complete official image.',
        );
      }
      if (!isImage) {
        throw const FormatException(
          'The downloaded file is not an ISO/IPSW image.',
        );
      }
      final completed = await partial.rename(
        p.join(target.path, source.fileName),
      );
      partial = null;
      savedPath = completed.path;
      status = DownloadStatus.succeeded;
    } catch (e) {
      if (!_cancelled) {
        status = DownloadStatus.failed;
        // Signed download URLs can contain temporary credentials. Do not log them.
        error = e is FormatException ? e.message : 'Could not download the image. Check the connection, free space, and link expiry, then retry.';
      }
    } finally {
      _client?.close(force: true);
      try {
        await writer?.close();
      } catch (_) {
        /* Preserve the original error. */
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {
        /* A .part file is never success. */
      }
      if (savedPath == null && target != null) {
        try {
          await target.delete();
        } catch (_) {
          /* Do not recursively remove unrelated files. */
        }
      }
      if (_cancelled && savedPath == null) status = DownloadStatus.cancelled;
      _changed();
      _done.complete();
    }
  }

  Future<void> cancel() async {
    if (finished) return;
    _cancelled = true;
    status = DownloadStatus.cancelling;
    _client?.close(force: true);
    _changed();
    if (_started) await done;
  }

  @override
  void dispose() {
    _disposed = true;
    if (!finished) unawaited(cancel());
    super.dispose();
  }
}
