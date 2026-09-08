import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickgui/src/globals.dart';
import 'package:quickgui/src/model/app_settings.dart';
import 'package:quickgui/src/pages/downloader_page.dart';
import 'package:quickgui/src/pages/main_page.dart';
import 'package:quickgui/src/pages/manager.dart';
import 'package:quickgui/src/services/vm_service.dart';
import 'package:quickgui/src/widgets/left_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

class EmptyRepository extends VmRepository {
  @override
  Future<List<VmRecord>> list(String directory) async => [];
}

void main() {
  testWidgets('original screens fit the minimum window and release resources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(692, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter/windowsize'),
      (_) async => null,
    );
    final fontDirectory = Platform.environment['QUICKGUI_TEST_FONT_DIR'];
    if (fontDirectory != null) {
      await tester.runAsync(() async {
        for (final font in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final bytes = await File('$fontDirectory/${font.value}')
              .readAsBytes();
          await (FontLoader(
            font.key,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
    }
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    final ops = VmOperations(repository: EmptyRepository());
    addTearDown(settings.dispose);
    addTearDown(ops.dispose);
    final key = GlobalKey();
    Widget wrap(Widget child) => ChangeNotifierProvider.value(
      value: settings,
      child: testApp(RepaintBoundary(key: key, child: child)),
    );
    for (final entry in {
      'home': const MainPage(),
      'download': const DownloaderPage(),
      'manager': Manager(operations: ops),
      'settings': const Scaffold(body: LeftMenu()),
    }.entries) {
      await tester.pumpWidget(wrap(entry.value));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/logo_pink.png'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: entry.key);
      final screenshots = Platform.environment['QUICKGUI_SCREENSHOT_DIR'];
      if (screenshots != null) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(screenshots).create(recursive: true);
          await File('$screenshots/${entry.key}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    // Theme is applied only after persistence succeeds, and survives reopening.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(prefThemeMode), isTrue);
    for (var i = 0; i < 30; i++) {
      await tester.pumpWidget(wrap(Manager(operations: ops)));
      await tester.pump();
      await tester.pumpWidget(wrap(const MainPage()));
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
