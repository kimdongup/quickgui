import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

import 'package:quickgui/src/model/operating_system.dart';
import 'package:quickgui/src/pages/operating_system_selection.dart';
import 'package:quickgui/src/widgets/selection_list.dart';

void main() {
  testWidgets('long selections scroll, filter and release controllers', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        SelectionList<int>(
          title: 'Select',
          searchHint: 'Search',
          items: List.generate(200, (i) => i),
          label: (i) => 'Operating system $i',
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Operating system 199'),
      500,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Operating system 199'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'system 0');
    await tester.pumpAndSettle();
    expect(find.text('Operating system 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'catalog failure shows retry, then an empty result rather than a spinner',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        testApp(
          OperatingSystemSelection(
            load: () async {
              if (calls++ == 0) throw const FormatException('bad catalog');
              return <OperatingSystem>[];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('bad catalog'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
