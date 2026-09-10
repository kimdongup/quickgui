import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/pages/apple_vm_create.dart';
import 'package:quickgui/src/services/apple_vm.dart';
import 'package:quickgui/src/widgets/apple_vm_controls.dart';
import 'package:quickgui/src/widgets/apple_vm_panel.dart';

import 'test_app.dart';

const channel = MethodChannel('quickgui/apple-vm');
const bundle = '/VM folder/My Mac.quickgui-macvm';
Map<String, Object?> record(String state, {String path = bundle}) => {
  'path': path,
  'name': 'My Mac',
  'version': '26.6.2',
  'state': state,
  if (state == 'installing') 'progress': .25,
};
const image = {
  'version': '26.6.2',
  'build': '25G83',
  'minimumCPU': 2,
  'maximumCPU': 7,
  'minimumMemoryGiB': 4,
  'maximumMemoryGiB': 6,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('only completed installations can run; unknown states are disabled', () {
    for (final state in [
      'installing',
      'cancelling',
      'failed',
      'cancelled',
      'interrupted',
      'busy',
      'error',
      'new-future-state',
    ]) {
      expect(AppleVmRecord(record(state)).canStart, isFalse, reason: state);
    }
    expect(AppleVmRecord(record('stopped')).canStart, isTrue);
    expect(AppleVmRecord(record('installing')).canStop, isFalse);
    expect(AppleVmRecord(record('running')).canShow, isTrue);
  });

  testWidgets('incompatible IPSW cannot create a VM', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspectImage');
      throw PlatformException(code: 'apple_vm', message: 'Incompatible IPSW');
    });
    await tester.pumpWidget(
      testApp(const AppleVmCreate(directory: '/VM folder', ipsw: '/bad.ipsw')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Incompatible IPSW'), findsOneWidget);
    expect(find.text('Create and install'), findsNothing);
    expect(find.text('Choose IPSW'), findsOneWidget);
  });

  testWidgets(
    'creation validates name, prevents duplicate clicks, polls install and starts saved bundle',
    (tester) async {
      tester.view.physicalSize = const Size(694, 610);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final created = Completer<Object?>();
      final calls = <MethodCall>[];
      var state = 'installing';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'inspectImage' => image,
          'create' => created.future,
          'status' => record(state),
          'start' => () {
            state = 'running';
            return null;
          }(),
          _ => throw StateError(call.method),
        };
      });
      await tester.pumpWidget(
        testApp(
          const AppleVmCreate(
            directory: '/VM folder',
            ipsw: '/Install Media/macOS image.ipsw',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '../existing');
      await tester.ensureVisible(find.text('Create and install'));
      await tester.tap(find.text('Create and install'));
      await tester.pumpAndSettle();
      expect(calls.where((e) => e.method == 'create'), isEmpty);
      await tester.enterText(find.byType(TextFormField), 'My Mac');
      await tester.ensureVisible(find.text('Create and install'));
      await tester.tap(find.text('Create and install'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls.singleWhere((e) => e.method == 'create').arguments, {
        'directory': '/VM folder',
        'name': 'My Mac',
        'ipsw': '/Install Media/macOS image.ipsw',
        'cpus': 2,
        'memoryGiB': 4,
        'diskGiB': 64,
      });
      created.complete(record('installing'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Installing macOS'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
      state = 'stopped';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump();
      expect(calls.singleWhere((e) => e.method == 'start').arguments, {
        'path': bundle,
      });
      expect(find.text('Open VM display'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(testApp(const SizedBox()));
    },
  );

  testWidgets('cancel is explicit and never force stops an installer', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: AppleVmControls(
            vm: AppleVmRecord(record('installing')),
            service: const AppleVmService(),
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.text('Force stop'), findsNothing);
    await tester.tap(find.text('Cancel installation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Cancel installation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'cancelInstall');
    expect(calls.single.arguments, {'path': bundle});
  });

  testWidgets(
    'force stop requires confirmation; shutdown is graceful by default',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: AppleVmControls(
              vm: AppleVmRecord(record('running')),
              service: const AppleVmService(),
              onChanged: () async {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Shut down'));
      await tester.pumpAndSettle();
      expect(calls.single.arguments, {'path': bundle, 'force': false});
      await tester.tap(find.text('Force stop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.length, 1);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'path': bundle, 'force': true});
    },
  );

  testWidgets(
    'Manager discovers persisted VM without Quickemu and discards stale workspace result',
    (tester) async {
      final first = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'supported') return true;
        if (call.method == 'list') {
          if ((call.arguments as Map)['directory'] == '/old') {
            return first.future;
          }
          return [record('stopped', path: '/new/My Mac.quickgui-macvm')];
        }
        throw StateError(call.method);
      });
      await tester.pumpWidget(testApp(const AppleVmPanel(directory: '/old')));
      await tester.pump();
      await tester.pumpWidget(testApp(const AppleVmPanel(directory: '/new')));
      first.complete([
        record('interrupted', path: '/old/My Mac.quickgui-macvm'),
      ]);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('/old/My Mac.quickgui-macvm'), findsNothing);
      expect(find.text('/new/My Mac.quickgui-macvm'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      await tester.pumpWidget(testApp(const SizedBox()));
    },
  );

  testWidgets('unsupported hosts do not show native VM actions', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'supported');
      return false;
    });
    await tester.pumpWidget(testApp(const AppleVmPanel(directory: '/test')));
    await tester.pumpAndSettle();
    expect(find.text('Create Apple Silicon VM'), findsNothing);
  });
}
