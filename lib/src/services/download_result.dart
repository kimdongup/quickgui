import 'dart:io';

import 'package:path/path.dart' as p;

import 'download_session.dart';
import 'vm_service.dart';

class DownloadedVm {
  const DownloadedVm(this.path, {required this.isNew});
  final String path;
  final bool isNew;

  static Future<Set<String>> snapshot(String directory) async => {
    await for (final file in Directory(directory).list(followLinks: false))
      if (file is File && file.path.endsWith('.conf'))
        p.normalize(p.absolute(file.path)),
  };

  /// Use the config named by quickget's success output, never folder timestamps.
  static Future<DownloadedVm?> fromSession(
    DownloadSession session,
    Set<String> before,
  ) async {
    if (session.status != DownloadStatus.succeeded) return null;
    final output = session.log.toString().replaceAll(
      RegExp(r'\x1b\[[0-9;]*m'),
      '',
    );
    final matches = RegExp(
      r'^\s*quickemu\s+--vm\s+(.+\.conf)\s*$',
      multiLine: true,
    ).allMatches(output);
    final paths = matches
        .map(
          (match) => p.normalize(
            p.absolute(p.join(session.directory, match[1]!.trim())),
          ),
        )
        .toSet();
    if (paths.length != 1) return null;
    final path = paths.single;
    if (p.dirname(path) != p.normalize(p.absolute(session.directory)) ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    final record = await const VmRepository().inspect(path);
    if (record == null || record.state == VmState.unknown) return null;
    return DownloadedVm(path, isNew: !before.contains(path));
  }
}
