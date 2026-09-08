import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/download_session.dart';
import 'package:quickgui/src/services/command_runner.dart';

class DelayedRunner extends CommandRunner {
  final ready = Completer<void>();
  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
  }) async {
    await ready.future;
    return super.start(
      executable,
      arguments,
      directory: directory,
      environment: environment,
    );
  }
}

void main() {
  DownloadSession session(
    String script, {
    CommandRunner runner = const CommandRunner(),
  }) => DownloadSession(
    executable: '/bin/sh',
    arguments: ['-c', script],
    directory: Directory.systemTemp.path,
    environment: Platform.environment,
    runner: runner,
  );
  test(
    'drains both large output pipes and recognizes a nonzero exit',
    () async {
      final download = session(
        'i=0; while [ "\$i" -lt 6000 ]; do echo "progress 40% aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; echo diagnostic >&2; i=\$((i+1)); done; exit 2',
      );
      await download.start().timeout(const Duration(seconds: 20));
      expect(download.status, DownloadStatus.failed);
      expect(download.exitCode, 2);
      expect(download.log.toString().length, lessThanOrEqualTo(65536));
      expect(download.progress, .4);
      download.dispose();
    },
  );
  test('100 percent is not success if the command fails afterwards', () async {
    final download = session('echo "100%" >&2; exit 1');
    await download.start();
    expect(download.status, DownloadStatus.failed);
    download.dispose();
  });
  test(
    'successful exit and missing executable have distinct results',
    () async {
      final success = session('exit 0');
      await success.start();
      expect(success.status, DownloadStatus.succeeded);
      final failure = DownloadSession(
        executable: '/does/not/exist',
        arguments: [],
        directory: Directory.systemTemp.path,
        environment: Platform.environment,
      );
      await failure.start();
      expect(failure.status, DownloadStatus.failed);
      expect(failure.error, isNotEmpty);
      success.dispose();
      failure.dispose();
    },
  );
  test('cancelling before process creation is not lost', () async {
    final runner = DelayedRunner();
    final download = session('sleep 60', runner: runner);
    final done = download.start();
    await download.cancel();
    runner.ready.complete();
    await done.timeout(const Duration(seconds: 10));
    expect(download.status, DownloadStatus.cancelled);
    download.dispose();
  });
  test('cancel terminates a child holding the output pipes open', () async {
    final download = session('sleep 60 & echo \$!; wait');
    final done = download.start();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (download.log.toString().trim().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final child = int.parse(download.log.toString().trim());
    await download.cancel();
    await done.timeout(const Duration(seconds: 10));
    expect(download.status, DownloadStatus.cancelled);
    final childStatus = await Process.run('/bin/ps', [
      '-p',
      '$child',
      '-o',
      'stat=',
    ]);
    expect(
      childStatus.exitCode != 0 ||
          (childStatus.stdout as String).trim().startsWith('Z'),
      isTrue,
    );
    download.dispose();
  });
  test('command arguments preserve spaces and Unicode', () async {
    final result = await const CommandRunner().run(
      '/usr/bin/printf',
      ['%s|', 'my VM.conf', '한글'],
      directory: Directory.systemTemp.path,
      environment: Platform.environment,
    );
    expect(result.stdout, 'my VM.conf|한글|');
  });
}
