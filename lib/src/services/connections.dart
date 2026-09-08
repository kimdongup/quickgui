import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'command_runner.dart';
import 'toolchain.dart';
import 'vm_service.dart';

/// Re-read running state and endpoints immediately before opening the viewer.
Future<List<String>> spiceArguments(
  VmRecord selected, {
  required VmRepository repository,
}) async {
  final current = await repository.inspect(selected.configPath);
  if (current == null ||
      current.state != VmState.running ||
      current.pid != selected.pid ||
      current.content != selected.content) {
    throw StateError('VM state changed; refresh and try again');
  }
  final path = current.spiceSocketPath;
  if (path != null && p.isAbsolute(path) && !path.contains('\u0000')) {
    // spice-gtk treats everything after spice+unix:// as a literal path. URI
    // percent-encoding would break spaces, percent signs and non-ASCII names.
    // Process.start passes this as one argument, without evaluating a shell.
    return ['--uri=spice+unix://$path'];
  }
  final port = current.spicePort;
  if (port != null && port > 0 && port <= 65535) {
    return ['-h', '127.0.0.1', '-p', '$port'];
  }
  throw StateError(
    'SPICE endpoint is no longer available; refresh and try again',
  );
}

Future<bool> detectSsh(
  int port, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
    var header = '';
    return await socket
        .any((data) {
          header += ascii.decode(data, allowInvalid: true);
          if (header.length > 4096) {
            throw const FormatException('Unexpected SSH banner');
          }
          return RegExp(r'(^|\n)SSH-').hasMatch(header);
        })
        .timeout(timeout);
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}

const terminals = [
  'osascript',
  'alacritty',
  'gnome-terminal',
  'mate-terminal',
  'konsole',
  'xfce4-terminal',
  'xterm',
  'lxterminal',
  'terminator',
  'tilix',
  'sakura',
  'guake',
  'uxterm',
  'cool-retro-term',
  'lxterm',
  'pterm',
  'uxrvt',
  'xrvt',
];
String? findTerminal(Toolchain tools) {
  final preferred = tools.find('x-terminal-emulator');
  if (preferred != null) {
    final resolved = File(preferred).resolveSymbolicLinksSync();
    if (terminals.contains(p.basenameWithoutExtension(resolved))) {
      return resolved;
    }
  }
  for (final name in terminals) {
    if (name == 'osascript' && !Platform.isMacOS) continue;
    final executable = tools.find(name);
    if (executable != null) return executable;
  }
  return null;
}

String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
List<String> sshArguments(String terminal, int port, String username) {
  if (port < 1 ||
      port > 65535 ||
      !RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$').hasMatch(username)) {
    throw const FormatException('Invalid SSH username or port');
  }
  final args = ['ssh', '-p', '$port', '-l', username, 'localhost'];
  switch (p.basenameWithoutExtension(terminal)) {
    case 'osascript':
      final command = args.map(shellQuote).join(' ');
      final literal = command.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      return ['-e', 'tell application "Terminal" to do script "$literal"'];
    case 'gnome-terminal':
    case 'mate-terminal':
      return ['--', ...args];
    case 'terminator':
    case 'xfce4-terminal':
      return ['-x', ...args];
    case 'guake':
      return ['-e', args.map(shellQuote).join(' ')];
    default:
      return ['-e', ...args];
  }
}

/// A viewer/terminal is allowed to remain open after the manager is closed.
Future<void> launchConnection(
  String executable,
  List<String> args, {
  required String directory,
  required Map<String, String> environment,
}) async {
  final child = await Process.start(
    executable,
    args,
    workingDirectory: directory,
    environment: environment,
    includeParentEnvironment: false,
  );
  final log = TailBuffer();
  final streams = Future.wait([
    child.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(log.add),
    child.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(log.add),
  ]);
  final exit = await child.exitCode;
  await streams;
  if (exit != 0) throw ProcessException(executable, args, log.toString(), exit);
}
