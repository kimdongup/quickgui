import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CommandResult {
  const CommandResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get message =>
      [stderr.trim(), stdout.trim()].where((s) => s.isNotEmpty).join('\n');
  void requireSuccess() {
    if (exitCode != 0) {
      throw ProcessException(
        'command',
        [],
        message.isEmpty ? 'Command failed (exit $exitCode)' : message,
        exitCode,
      );
    }
  }
}

class TailBuffer {
  TailBuffer([this.limit = 65536]);
  final int limit;
  String _text = '';
  void add(String text) {
    _text += text;
    if (_text.length > limit) _text = _text.substring(_text.length - limit);
  }

  @override
  String toString() => _text;
}

class CommandRunner {
  const CommandRunner();
  Future<Process> start(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    environment: environment,
    includeParentEnvironment: false,
  );

  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
    Duration timeout = const Duration(seconds: 30),
    int outputLimit = 65536,
  }) async {
    final process = await start(
      executable,
      arguments,
      directory: directory,
      environment: environment,
    );
    final out = TailBuffer(outputLimit), err = TailBuffer(outputLimit);
    final streams = Future.wait([
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(out.add),
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(err.add),
    ]);
    try {
      final result = await Future.wait<Object>([process.exitCode, streams])
          .timeout(timeout);
      return CommandResult(result.first as int, out.toString(), err.toString());
    } on TimeoutException {
      await terminateProcessTree(process);
      throw ProcessException(executable, arguments, 'Command timed out');
    }
  }
}

/// Cancel only this command and descendants captured from the process tree.
/// Identity stamps prevent a recycled child PID from receiving a later signal.
Future<void> terminateProcessTree(Process process) async {
  if (Platform.isWindows) {
    process.kill();
    return;
  }
  Future<Map<int, (int, String)>> snapshot() async {
    final result = await Process.run('/bin/ps', ['-axo', 'pid=,ppid=,lstart=']);
    if (result.exitCode != 0) {
      throw const ProcessException('ps', [], 'Cannot inspect child processes');
    }
    final entries = <int, (int, String)>{};
    for (final line in (result.stdout as String).split('\n')) {
      final match = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+)$').firstMatch(line);
      if (match != null) {
        entries[int.parse(match[1]!)] = (int.parse(match[2]!), match[3]!);
      }
    }
    return entries;
  }

  final initial = await snapshot();
  if (!initial.containsKey(process.pid)) return;
  final owned = <int, String>{process.pid: initial[process.pid]!.$2};
  // Stop the root while enumerating so it cannot launch more downloads.
  process.kill(ProcessSignal.sigstop);
  try {
    for (var round = 0; round < 8; round++) {
      final current = await snapshot();
      var added = false;
      for (final entry in current.entries) {
        if (owned.containsKey(entry.value.$1) &&
            !owned.containsKey(entry.key)) {
          owned[entry.key] = entry.value.$2;
          Process.killPid(entry.key, ProcessSignal.sigstop);
          added = true;
        }
      }
      if (!added) break;
    }
    for (final pid in owned.keys.toList().reversed) {
      final current = await snapshot();
      if (current[pid]?.$2 == owned[pid]) {
        Process.killPid(pid, ProcessSignal.sigterm);
        Process.killPid(pid, ProcessSignal.sigcont);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final remaining = await snapshot();
    for (final pid in owned.keys.toList().reversed) {
      if (remaining[pid]?.$2 == owned[pid]) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
  } finally {
    // Never leave a stopped command behind if inspecting the process table fails.
    process.kill(ProcessSignal.sigcont);
  }
}
