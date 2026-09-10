import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/model/operating_system.dart';
import 'package:quickgui/src/pages/arm_media_download.dart';
import 'package:quickgui/src/pages/operating_system_selection.dart';
import 'package:quickgui/src/pages/version_selection.dart';
import 'package:quickgui/src/services/arm_media.dart';
import 'package:quickgui/src/services/guest_catalog.dart';

import 'test_app.dart';

void main() {
  testWidgets(
    'OS selection distinguishes architecture and ARM version retains it',
    (tester) async {
      tester.view.physicalSize = const Size(694, 610);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        testApp(
          OperatingSystemSelection(
            load: () async => [
              OperatingSystem('macOS', 'macos'),
              OperatingSystem('Windows', 'windows'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('macOS — Intel x64'), findsOneWidget);
      expect(find.text('macOS — Apple Silicon ARM64'), findsOneWidget);
      expect(find.text('Windows — ARM64'), findsOneWidget);
      expect(find.text('Windows — x64'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ARM64');
      await tester.pumpAndSettle();
      expect(find.text('Windows — x64'), findsNothing);
      expect(find.text('Windows — ARM64'), findsOneWidget);
      final os = withArmMedia([])
          .firstWhere((e) => e.armMedia == ArmMedia.windows);
      await tester.pumpWidget(testApp(VersionSelection(operatingSystem: os)));
      await tester.pumpAndSettle();
      expect(find.text('Select version for Windows — ARM64'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Windows route explains official link and refuses an x64 ISO', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const ArmMediaDownload(
          kind: ArmMedia.windows,
          directory: '/test workspace',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open Microsoft ARM64 downloads'), findsOneWidget);
    expect(
      find.textContaining('virtual machine is a separate step'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField),
      'https://software.download.prss.microsoft.com/Win11_x64.iso',
    );
    await tester.ensureVisible(find.text('Download ISO'));
    await tester.tap(find.text('Download ISO'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not the web page or an x64 ISO'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS metadata failure can retry without starting a download', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      testApp(
        ArmMediaDownload(
          kind: ArmMedia.macos,
          directory: '/test workspace',
          restoreImage: () async {
            if (calls++ == 0) throw PlatformException(code: 'offline');
            return MediaSource(
              kind: ArmMedia.macos,
              url: Uri.parse('https://updates.cdn-apple.com/restore.ipsw'),
              label: 'macOS test build — Apple Silicon ARM64',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not find a compatible image'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('macOS test build — Apple Silicon ARM64'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
