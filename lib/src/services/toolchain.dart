import 'dart:io';

import 'package:path/path.dart' as p;

/// One environment for discovery and every child process. Keep user PATH first.
class Toolchain {
  Toolchain({Map<String, String>? environment, bool? isMacOS})
    : environment = {...(environment ?? Platform.environment)} {
    final entries = <String>[
      ...?this.environment['PATH']?.split(':'),
      if (isMacOS ?? Platform.isMacOS) ...[
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ],
      if (this.environment['HOME'] case final String home) '$home/.local/bin',
      '/run/current-system/sw/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
    ];
    this.environment['PATH'] = entries
        .where((e) => e.isNotEmpty)
        .map(p.absolute)
        .toSet()
        .join(':');
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
