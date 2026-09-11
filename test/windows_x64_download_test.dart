import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/pages/windows_x64_download.dart';

void main() {
  testWidgets(
    'x64 setup offers manual ISO selection and cannot create without media',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WindowsX64Download(directory: '/unused')),
      );
      expect(find.text('Windows 11 — x64'), findsOneWidget);
      expect(find.text('Choose existing ISO'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Create VM'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create VM'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
