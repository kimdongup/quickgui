import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

var gIsSnap = Platform.environment['SNAP']?.isNotEmpty ?? false;
final Map<String, String> gProcessEnvironment = {...Platform.environment};
String? gQuickgetExecutable;
String? gQuickemuExecutable;
const String prefWorkingDirectory = 'workingDirectory';
const String prefThemeMode = 'themeMode';
const String prefCurrentLocale = 'currentLocale';

Future<void> configureWorkingDirectory() async {
  final preferences = await SharedPreferences.getInstance();
  final savedPath = preferences.getString(prefWorkingDirectory);
  final homeDirectory = Platform.environment['HOME'];
  final fallbackPath = homeDirectory == null || homeDirectory.isEmpty
      ? '${Directory.systemTemp.path}${Platform.pathSeparator}Quickemu'
      : '$homeDirectory${Platform.pathSeparator}Quickemu';

  final savedDirectory = savedPath == null ? null : Directory(savedPath);
  final canUseSavedDirectory = savedDirectory != null &&
      savedDirectory.path != Platform.pathSeparator &&
      savedDirectory.existsSync();
  final workingDirectory =
      canUseSavedDirectory ? savedDirectory : Directory(fallbackPath);
  if (!workingDirectory.existsSync()) {
    await workingDirectory.create(recursive: true);
  }

  Directory.current = workingDirectory.path;
  if (savedPath != workingDirectory.path) {
    await preferences.setString(prefWorkingDirectory, workingDirectory.path);
  }
}

void configureProcessEnvironment() {
  final homeDirectory = Platform.environment['HOME'];
  final pathSeparator = Platform.isWindows ? ';' : ':';
  final pathEntries = <String>[
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/run/current-system/sw/bin',
    if (homeDirectory != null && homeDirectory.isNotEmpty)
      '$homeDirectory/.local/bin',
    ...?gProcessEnvironment['PATH']?.split(pathSeparator),
  ];
  gProcessEnvironment['PATH'] = pathEntries.toSet().join(pathSeparator);
  gQuickgetExecutable = findExecutable('quickget');
  gQuickemuExecutable = findExecutable('quickemu');
}

String? findExecutable(String name) {
  final path = gProcessEnvironment['PATH'];
  if (path == null || path.isEmpty) {
    return null;
  }

  final pathSeparator = Platform.isWindows ? ';' : ':';
  for (final directory in path.split(pathSeparator)) {
    if (directory.isEmpty) {
      continue;
    }
    final candidate = File('$directory${Platform.pathSeparator}$name');
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}

Future<String> fetchQuickemuVersion() async {
  final executable = gQuickemuExecutable;
  if (executable == null) {
    return '';
  }

  // Get the version of quickemu
  var result = await Process.run(
    executable,
    ['--version'],
    environment: gProcessEnvironment,
  );

  // If successful return the trimmed version
  if (result.exitCode == 0) {
    return result.stdout.trim();
  } else {
    return '';
  }
}
