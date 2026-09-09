import 'dart:io';

import 'package:path/path.dart' as p;

/// One environment for discovery and every child process.
/// On macOS, prefer Homebrew over system tools while retaining leading overrides.
class Toolchain {
  Toolchain({Map<String, String>? environment, bool? isMacOS})
    : environment = {...(environment ?? Platform.environment)} {
    const homebrew = ['/opt/homebrew/bin', '/usr/local/bin'];
    final macOS = isMacOS ?? Platform.isMacOS;
    final entries = <String>[
      ...?this.environment['PATH']?.split(':'),
      if (macOS) ...homebrew,
      if (this.environment['HOME'] case final String home) '$home/.local/bin',
      '/run/current-system/sw/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
    ].where((e) => e.isNotEmpty).map(p.absolute).toSet().toList();
    if (macOS) {
      // Quickemu/Quickget use #!/usr/bin/env bash, including in child scripts.
      // Appending Homebrew leaves macOS's Bash 3.2 ahead of the required Bash 4+.
      const system = ['/usr/bin', '/bin', '/usr/sbin', '/sbin'];
      final index = entries.indexWhere(
        (entry) => homebrew.contains(entry) || system.contains(entry),
      );
      entries.removeWhere(homebrew.contains);
      entries.insertAll(index, homebrew);
    }
    this.environment['PATH'] = entries.join(':');
  }

  final Map<String, String> environment;

  String? find(String name) {
    final candidates = p.isAbsolute(name)
        ? [name]
        : environment['PATH']!.split(':').map((dir) => p.join(dir, name));
    for (final candidate in candidates) {
      try {
        final stat = File(candidate).statSync();
        if (stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0) {
          // Mode bits alone are insufficient for files owned by another user.
          if (Process.runSync('/bin/test', ['-x', candidate]).exitCode == 0) {
            return p.normalize(p.absolute(candidate));
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }
}
