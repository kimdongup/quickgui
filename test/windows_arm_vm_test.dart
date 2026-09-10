import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/pages/native_vm_create.dart';
import 'package:quickgui/src/services/native_vm.dart';
import 'package:quickgui/src/widgets/native_vm_controls.dart';
import 'package:quickgui/src/widgets/native_vm_panel.dart';

import 'test_app.dart';

const channel = MethodChannel('quickgui/windows-arm-vm');
const service = NativeVmService(kind: NativeVmKind.windows);
const path = '/Windows VMs/My Windows.quickgui-winarm';
Map<String, Object> vm({bool pending = true, String state = 'stopped'}) => {
  'path': path,
  'name': 'My Windows',
  'state': state,
  'version': '11 ARM64',
  'installationPending': pending,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'network help is available during OOBE without starting or completing the VM',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: NativeVmControls(
              vm: NativeVmRecord(vm(state: 'running')),
              service: service,
              onChanged: () async {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Network setup'));
      await tester.pumpAndSettle();
      expect(find.text('Windows network setup'), findsOneWidget);
      expect(find.textContaining('QGNET'), findsOneWidget);
      expect(find.textContaining('NetKVM'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Windows network setup'), findsNothing);
    },
  );

  testWidgets(
    'Windows creation uses its own channel and reports storage refusal without success',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'inspectImage') {
          return {
            'version': '11 ARM64',
            'build': 'Microsoft ISO',
            'minimumCPU': 2,
            'maximumCPU': 7,
            'minimumMemoryGiB': 4,
            'maximumMemoryGiB': 6,
          };
        }
        if (call.method == 'create') {
          throw PlatformException(
            code: 'storage',
            message: 'At least 32 GiB of free host storage is required.',
          );
        }
        throw StateError(call.method);
      });
      await tester.pumpWidget(
        testApp(
          const NativeVmCreate(
            directory: '/Windows VMs',
            imagePath: '/Downloads/Windows, Korean ARM64.iso',
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create Windows ARM64 VM'), findsOneWidget);
      expect(find.text('Choose ARM64 ISO'), findsOneWidget);
      expect(find.text('Choose IPSW'), findsNothing);
      await tester.ensureVisible(find.text('Create and install'));
      await tester.tap(find.text('Create and install'));
      await tester.pumpAndSettle();
      expect(calls.singleWhere((c) => c.method == 'create').arguments, {
        'directory': '/Windows VMs',
        'name': 'Windows 11 ARM64',
        'image': '/Downloads/Windows, Korean ARM64.iso',
        'cpus': 2,
        'memoryGiB': 4,
        'diskGiB': 64,
      });
      expect(find.textContaining('At least 32 GiB'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows installer is resumed explicitly; completion requires user confirmation while stopped',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: NativeVmControls(
              vm: NativeVmRecord(vm()),
              service: service,
              onChanged: () async {},
            ),
          ),
        ),
      );
      expect(find.text('Resume installation'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
      await tester.tap(find.text('Installation completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('without the installation ISO'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Installation completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'completeInstallation');
      expect(calls.single.arguments, {'path': path});
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: NativeVmControls(
              vm: NativeVmRecord(vm(state: 'running')),
              service: service,
              onChanged: () async {},
            ),
          ),
        ),
      );
      expect(find.text('Installation completed'), findsNothing);
    },
  );

  testWidgets(
    'completed Windows VM is rediscovered and starts without passing an ISO',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'supported' => true,
          'list' => [vm(pending: false)],
          'start' => null,
          _ => throw StateError(call.method),
        };
      });
      await tester.pumpWidget(
        testApp(
          const NativeVmPanel(directory: '/Windows VMs', service: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create Windows ARM64 VM'), findsOneWidget);
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(calls.singleWhere((c) => c.method == 'start').arguments, {
        'path': path,
      });
      await tester.pumpWidget(testApp(const SizedBox()));
    },
  );
}
