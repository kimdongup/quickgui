import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/pages/installation_media.dart';
import 'package:quickgui/src/services/native_vm.dart';
import 'package:quickgui/src/widgets/native_vm_controls.dart';

import 'test_app.dart';

const channel = MethodChannel('quickgui/native-storage');
const imagePath = '/Downloads/Windows, ARM64.iso';
const vmPath = '/VMs/My Mac.quickgui-macvm';
Map<String, Object> preview({bool vm = false}) => {
  'path': vm ? vmPath : imagePath,
  'name': vm ? 'My Mac' : 'Windows, ARM64.iso',
  'bytes': 1024 * 1024 * 1024,
  'token': 'reviewed-file-identity',
  'isVM': vm,
};
Map<String, Object> media() => {
  'path': imagePath,
  'name': 'Windows, ARM64.iso',
  'kind': 'ISO',
  'bytes': 1024 * 1024 * 1024,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Delete installation file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'media confirmation names the exact path and cancel never deletes',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'listMedia' => [media()],
          'preview' => preview(),
          _ => throw StateError('Unexpected deletion'),
        };
      });
      await tester.pumpWidget(
        testApp(const InstallationMedia(directory: '/VMs')),
      );
      await tester.pumpAndSettle();
      await openDialog(tester);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(imagePath),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Delete permanently'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'a different image');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Delete permanently'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'delete'), isEmpty);
      expect(find.text('Windows, ARM64.iso'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmed media deletion sends preview token and refreshes list',
    (tester) async {
      MethodCall? deletion;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listMedia') {
          return deletion == null ? [media()] : [];
        }
        if (call.method == 'preview') return preview();
        if (call.method == 'delete') {
          deletion = call;
          return null;
        }
        throw StateError(call.method);
      });
      await tester.pumpWidget(
        testApp(const InstallationMedia(directory: '/VMs')),
      );
      await tester.pumpAndSettle();
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'Windows, ARM64.iso');
      await tester.pump();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(deletion?.arguments, {
        'path': imagePath,
        'directory': '/VMs',
        'token': 'reviewed-file-identity',
        'isVM': false,
      });
      expect(find.text('No installation files found.'), findsOneWidget);
      expect(find.text('Windows, ARM64.iso'), findsNothing);
    },
  );

  testWidgets('in-use preview rejection keeps the file and never confirms', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listMedia') return [media()];
      if (call.method == 'preview') {
        throw PlatformException(
          code: 'native_storage',
          message: 'This image is still needed to install Windows.',
        );
      }
      throw StateError('Unexpected deletion');
    });
    await tester.pumpWidget(
      testApp(const InstallationMedia(directory: '/VMs')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete installation file'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('still needed'), findsOneWidget);
    expect(find.text('Windows, ARM64.iso'), findsOneWidget);
  });

  testWidgets('changed file error after confirmation does not remove its row', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listMedia') return [media()];
      if (call.method == 'preview') return preview();
      if (call.method == 'delete') {
        throw PlatformException(
          code: 'native_storage',
          message: 'The selected item changed.',
        );
      }
      throw StateError(call.method);
    });
    await tester.pumpWidget(
      testApp(const InstallationMedia(directory: '/VMs')),
    );
    await tester.pumpAndSettle();
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'Windows, ARM64.iso');
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.text('The selected item changed.'), findsOneWidget);
    expect(find.text('Windows, ARM64.iso'), findsOneWidget);
  });

  testWidgets('native VM deletion is offered only for inactive known states', (
    tester,
  ) async {
    MethodCall? deleted;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'preview') return preview(vm: true);
      if (call.method == 'delete') {
        deleted = call;
        return null;
      }
      throw StateError(call.method);
    });
    var refreshes = 0;
    Widget controls(String state) => testApp(
      Scaffold(
        body: NativeVmControls(
          vm: NativeVmRecord({
            'path': vmPath,
            'name': 'My Mac',
            'state': state,
          }),
          service: const NativeVmService(),
          allowDelete: true,
          onChanged: () async {
            refreshes++;
          },
        ),
      ),
    );
    for (final state in [
      'running',
      'installing',
      'starting',
      'stopping',
      'cancelling',
      'busy',
      'error',
    ]) {
      await tester.pumpWidget(controls(state));
      expect(find.text('Delete VM'), findsNothing, reason: state);
    }
    await tester.pumpWidget(controls('interrupted'));
    await tester.tap(find.text('Delete VM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('all files inside its folder'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My Mac');
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(deleted?.arguments, {
      'path': vmPath,
      'directory': '/VMs',
      'token': 'reviewed-file-identity',
      'isVM': true,
    });
    expect(refreshes, 1);
  });
}
