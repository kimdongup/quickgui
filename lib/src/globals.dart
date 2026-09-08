import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/command_runner.dart';
import 'services/toolchain.dart';
import 'services/workspace.dart';
import 'services/backend_settings.dart';

final gIsSnap = Platform.environment['SNAP']?.isNotEmpty ?? false;
Toolchain gToolchain = Toolchain();
CommandRunner gRunner = const CommandRunner();
Workspace? gWorkspace;
BackendSettings gBackendSettings = const BackendSettings();
String? gStartupError;
String? gQuickgetExecutable;
String? gQuickemuExecutable;
Map<String, String> get gProcessEnvironment => gToolchain.environment;
const String prefWorkingDirectory = Workspace.preferenceKey;
const String prefThemeMode = 'themeMode';
const String prefCurrentLocale = 'currentLocale';
String get workingDirectory => gWorkspace?.path ?? Directory.current.path;
String? findExecutable(String name) => gToolchain.find(name);

void configureProcessEnvironment() {
  gToolchain = Toolchain();
  gQuickgetExecutable = findExecutable(
    gBackendSettings.quickget.isEmpty ? 'quickget' : gBackendSettings.quickget,
  );
  gQuickemuExecutable = findExecutable(
    gBackendSettings.quickemu.isEmpty ? 'quickemu' : gBackendSettings.quickemu,
  );
}

Future<void> configureWorkingDirectory() async {
  final preferences = await SharedPreferences.getInstance();
  gWorkspace?.dispose();
  gWorkspace = Workspace(
    preferences: preferences,
    defaultPath: p.join(
      Platform.environment['HOME'] ?? Directory.systemTemp.path,
      'Quickemu',
    ),
  );
  await gWorkspace!.initialize();
}

Future<String> fetchQuickemuVersion() async {
  final executable = gQuickemuExecutable;
  if (executable == null) return '';
  try {
    final result = await gRunner.run(
      executable,
      ['--version'],
      environment: gProcessEnvironment,
      directory: Directory.systemTemp.path,
    );
    return result.exitCode == 0 ? result.stdout.trim() : '';
  } on ProcessException {
    return '';
  }
}
