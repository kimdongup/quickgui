import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'command_runner.dart';

enum DownloadStatus {
  starting,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
}

class DownloadSession extends ChangeNotifier {
  DownloadSession({
    required this.executable,
    required this.arguments,
    required this.directory,
    required this.environment,
    this.runner = const CommandRunner(),
  });
  final String executable;
  final List<String> arguments;
  final String directory;
  final Map<String, String> environment;
  final CommandRunner runner;
  final log = TailBuffer();
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  DownloadStatus status = DownloadStatus.starting;
  double? progress;
  String? error;
  int? exitCode;
  Process? _process;
  bool _cancelRequested = false, _disposed = false, _started = false;
  Future<void>? _termination;
  String _progressTail = '';

  bool get finished => [
    DownloadStatus.succeeded,
    DownloadStatus.failed,
    DownloadStatus.cancelled,
  ].contains(status);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _output(String chunk) {
    log.add(chunk);
    _progressTail += chunk;
    final matches = RegExp(r'(\d+(?:\.\d+)?)%').allMatches(_progressTail);
    if (matches.isNotEmpty) {
      progress = (double.parse(matches.last[1]!) / 100).clamp(0.0, 1.0);
    }
    // Preserve partial progress tokens crossing stream chunks.
    if (_progressTail.length > 128) {
      _progressTail = _progressTail.substring(_progressTail.length - 128);
    }
    _changed();
  }

  Future<void> start() async {
    if (_started) throw StateError('Download already started');
    _started = true;
    try {
      _process = await runner.start(
        executable,
        arguments,
        directory: directory,
        environment: environment,
      );
      final process = _process!;
      final streams = Future.wait([
        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .forEach(_output),
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .forEach(_output),
      ]);
      status = _cancelRequested
          ? DownloadStatus.cancelling
          : DownloadStatus.running;
      _changed();
      if (_cancelRequested) await _terminate();
      exitCode = await process.exitCode;
      await streams;
      if (_termination != null) await _termination;
      status = exitCode == 0
          ? DownloadStatus.succeeded
          : _cancelRequested
          ? DownloadStatus.cancelled
          : DownloadStatus.failed;
      if (status == DownloadStatus.failed) {
        error = log.toString().trim().isEmpty
            ? 'Download failed (exit $exitCode)'
            : log.toString().trim();
      }
    } catch (e) {
      status = DownloadStatus.failed;
      error = '$e';
    } finally {
      _changed();
      _done.complete();
    }
  }

  Future<void> _terminate() => _termination ??= terminateProcessTree(_process!);

  Future<void> cancel() async {
    if (finished) return;
    _cancelRequested = true;
    status = DownloadStatus.cancelling;
    _changed();
    if (_process != null) {
      try {
        await _terminate();
      } catch (e) {
        error = 'Unable to cancel download: $e';
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!finished) unawaited(cancel());
    super.dispose();
  }
}
