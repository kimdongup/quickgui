import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';

import 'dart:io';

import 'src/app.dart';
import 'src/globals.dart';
import 'src/mixins/app_version.dart';
import 'src/model/app_settings.dart';
import 'src/model/operating_system.dart';
import 'src/model/osicons.dart';
import 'src/services/catalog.dart';

Future<List<OperatingSystem>> loadOperatingSystems([
  bool showUbuntus = false,
]) async {
  final executable = gQuickgetExecutable;
  if (executable == null) {
    throw const ProcessException('quickget', [], 'quickget was not found');
  }
  final result = await gRunner.run(
    executable,
    ['--list-csv'],
    environment: gProcessEnvironment,
    directory: workingDirectory,
    timeout: const Duration(minutes: 2),
    outputLimit: 8 * 1024 * 1024,
  );
  result.requireSuccess();
  return parseCatalog(result.stdout);
}

Future<void> getIcons() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  osIcons.clear();
  for (final asset in manifest.listAssets()) {
    if (asset.startsWith('assets/quickemu-icons/') && asset.endsWith('.svg')) {
      final file = asset.split('/').last;
      osIcons[file.substring(0, file.length - 4)] = asset;
    }
  }
}

Future<void> initializeRuntime() async {
  gStartupError = null;
  configureProcessEnvironment();
  try {
    await configureWorkingDirectory();
  } catch (error) {
    gStartupError = 'Unable to load workspace settings: $error';
  }
  // App metadata and optional icons do not determine whether Quickemu is installed.
  try {
    AppVersion.packageInfo = await PackageInfo.fromPlatform();
  } catch (_) {
    AppVersion.packageInfo = null;
  }
  try {
    await getIcons();
  } catch (_) {
    osIcons.clear();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    setWindowMinSize(const Size(694, 610));
    setWindowMaxSize(const Size(694, 610));
  } else {
    setWindowMinSize(const Size(692, 580));
    setWindowMaxSize(const Size(800, 720));
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppSettings(),
      child: App(initialize: initializeRuntime),
    ),
  );
}
