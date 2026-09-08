import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/main.dart' as app;
import 'package:quickgui/src/model/osicons.dart';
import 'package:quickgui/src/services/catalog.dart';
import 'package:quickgui/src/services/toolchain.dart';
import 'package:quickgui/src/services/workspace.dart';
import 'package:quickgui/src/mixins/preferences_mixin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs with PreferencesMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loads icons from the bundled binary manifest', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets().any((p) => p.contains('quickemu-icons')),
      isTrue,
    );
    await app.getIcons();
    expect(osIcons, isNotEmpty);
  });
  test(
    'parses legacy, current and quoted catalogs without duplicate versions',
    () {
      final os = parseCatalog(
        'Display Name,OS,Release,Option,Downloader,PNG,SVG\r\n'
        '"A, Linux",alinux,1,desktop,curl,,\r\n'
        'Other,other,1,,curl,,\n'
        '"A, Linux",alinux,1,server,curl,,\n',
      );
      expect(os.first.name, 'A, Linux');
      expect(os.first.versions.single.options.length, 2);
      expect(
        parseCatalog('Name,OS,Release,Option\nA,a,1,\n')
            .single
            .versions
            .single
            .options
            .single
            .downloader,
        'curl',
      );
      expect(
        () => parseCatalog('Name,OS,Release,Option\ninvalid\n'),
        throwsFormatException,
      );
      expect(
        () => parseCatalog('ERROR: command failed'),
        throwsFormatException,
      );
      expect(() => csvRows('"unterminated'), throwsFormatException);
    },
  );
  test('preserves PATH order and ignores a non-executable file', () async {
    final tmp = await Directory.systemTemp.createTemp('quickgui-tools-');
    try {
      final first = await Directory('${tmp.path}/first').create();
      final second = await Directory('${tmp.path}/second dir').create();
      for (final dir in [first, second]) {
        await File('${dir.path}/quickgui-test-command')
            .writeAsString('#!/bin/sh\nexit 0\n');
      }
      await Process.run('/bin/chmod', [
        '+x',
        '${second.path}/quickgui-test-command',
      ]);
      final tools = Toolchain(
        environment: {'PATH': '${first.path}:${second.path}'},
        isMacOS: true,
      );
      expect(
        tools.find('quickgui-test-command'),
        '${second.path}/quickgui-test-command',
      );
      await Process.run('/bin/chmod', [
        '+x',
        '${first.path}/quickgui-test-command',
      ]);
      expect(
        tools.find('quickgui-test-command'),
        '${first.path}/quickgui-test-command',
      );
    } finally {
      await tmp.delete(recursive: true);
    }
  });
  test(
    'unavailable saved workspace is preserved; recovery does not change cwd',
    () async {
      final tmp = await Directory.systemTemp.createTemp('quickgui-workspace-');
      final current = Directory.current.path;
      try {
        final absent = '${tmp.path}/missing';
        SharedPreferences.setMockInitialValues({'workingDirectory': absent});
        final prefs = await SharedPreferences.getInstance();
        final workspace = Workspace(
          preferences: prefs,
          defaultPath: '${tmp.path}/default',
        );
        await workspace.initialize();
        expect(workspace.available, isFalse);
        expect(prefs.getString('workingDirectory'), absent);
        await workspace.select(tmp.path);
        expect(workspace.available, isTrue);
        expect(Directory.current.path, current);
        final existing = File('${tmp.path}/modecheck.tmp');
        await existing.writeAsString('user data');
        await workspace.verifyWritable();
        expect(await existing.readAsString(), 'user data');
        expect(await tmp.list().length, 1);
        workspace.dispose();
      } finally {
        await tmp.delete(recursive: true);
      }
    },
  );
  test('string-list preferences round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Prefs();
    await prefs.savePreference('list', <String>['vm one', 'vm two']);
    expect(await prefs.getPreference<List<String>>('list'), [
      'vm one',
      'vm two',
    ]);
  });
}
