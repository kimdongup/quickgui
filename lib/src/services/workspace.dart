import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class Workspace extends ChangeNotifier {
  Workspace({required this.preferences, required this.defaultPath});
  final SharedPreferences preferences;
  final String defaultPath;
  static const preferenceKey = 'workingDirectory';
  String? _path;
  String? error;
  int generation = 0;

  String get path => _path ?? p.normalize(p.absolute(defaultPath));
  bool get available => _path != null && error == null;

  Future<void> initialize() async {
    String? saved;
    try {
      saved = preferences.getString(preferenceKey);
      final candidate = saved == null || saved.trim().isEmpty
          ? defaultPath
          : saved;
      if (saved == null || saved.trim().isEmpty) {
        await Directory(candidate).create(recursive: true);
      }
      await select(candidate, persist: false);
    } catch (e) {
      _path = null;
      error = 'Unable to access ${saved ?? defaultPath}: $e';
      notifyListeners();
    }
  }

  Future<void> select(String directory, {bool persist = true}) async {
    if (directory.trim().isEmpty) {
      throw const FileSystemException('Empty directory');
    }
    final selected = p.normalize(p.absolute(directory));
    if (!await Directory(selected).exists()) {
      throw FileSystemException('Directory is unavailable', selected);
    }
    // Opening an enumeration verifies directory access without touching VM data.
    await Directory(selected).list(followLinks: false).take(1).drain<void>();
    if (persist && !await preferences.setString(preferenceKey, selected)) {
      throw const FileSystemException('Could not save the selected directory');
    }
    _path = selected;
    error = null;
    generation++;
    notifyListeners();
  }

  Future<void> verifyWritable() async {
    if (!available) throw FileSystemException(error ?? 'Select a VM directory');
    final probe = await Directory(path).createTemp('.quickgui-probe-');
    try {
      await File(p.join(probe.path, 'write'))
          .writeAsString('probe', flush: true);
    } finally {
      await probe.delete(recursive: true);
    }
  }
}
