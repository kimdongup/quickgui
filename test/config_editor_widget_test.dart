import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/pages/config_editor.dart';
import 'package:quickgui/src/services/vm_service.dart';

import 'test_app.dart';

class SavingOperations extends VmOperations {
  final done = Completer<void>();
  String? saved;
  @override
  Future<void> saveConfig(VmRecord selected, String content) async {
    saved = content;
    await done.future;
  }
}

void main() {
  testWidgets(
    'editor disables Save while loading/saving and returns only after save',
    (tester) async {
      late Directory directory;
      late File file;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'quickgui-editor-widget-',
        );
        file = await File('${directory.path}/vm.conf')
            .writeAsString('# original\n');
      });
      addTearDown(() => directory.delete(recursive: true));
      final operations = SavingOperations();
      addTearDown(operations.dispose);
      final vm = VmRecord(
        configPath: file.path,
        content: '# original\n',
        state: VmState.stopped,
      );
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ConfigEditor(vm: vm, operations: operations),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );
      // Each file open/read/close completion needs an event-loop turn outside
      // Flutter's fake clock, followed by pumping its continuation.
      for (
        var i = 0;
        i < 20 && !tester.widget<TextField>(find.byType(TextField)).enabled!;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '# original\nram="4G"\n');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(operations.saved, '# original\nram="4G"\n');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pump();
      expect(find.byType(ConfigEditor), findsOneWidget);
      operations.done.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ConfigEditor), findsNothing);
      expect(find.text('Open editor'), findsOneWidget);
      expect(await tester.runAsync(file.readAsString), '# original\n');
    },
  );
}
