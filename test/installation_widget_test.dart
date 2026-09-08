import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/globals.dart';
import 'package:quickgui/src/pages/manager.dart';
import 'package:quickgui/src/services/vm_service.dart';

import 'test_app.dart';

class InstallationRepository extends VmRepository {
  bool pending = true;
  @override
  Future<List<VmRecord>> list(String directory) async => [
    VmRecord(
      configPath: '/test/windows.conf',
      content: 'guest_os="windows"\ndisk_img="windows/disk.qcow2"\n',
      state: VmState.stopped,
      installationPending: pending,
    ),
  ];
}

class InstallationOperations extends VmOperations {
  InstallationOperations(InstallationRepository repository)
    : super(repository: repository);
  final actions = <VmAction>[];
  @override
  Future<void> perform(
    VmRecord selected,
    VmAction action, {
    required String executable,
    required Map<String, String> environment,
    List<String> startArguments = const [],
  }) async {
    actions.add(action);
    if (action == VmAction.confirmInstallation) {
      (repository as InstallationRepository).pending = false;
    }
  }
}

void main() {
  testWidgets(
    'Run requires explicit installation confirmation and a separate second Run',
    (tester) async {
      tester.view.physicalSize = const Size(692, 580);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = gQuickemuExecutable;
      gQuickemuExecutable = '/unused';
      addTearDown(() => gQuickemuExecutable = original);
      final ops = InstallationOperations(InstallationRepository());
      addTearDown(ops.dispose);
      await tester.pumpWidget(testApp(Manager(operations: ops)));
      await tester.pumpAndSettle();
      expect(find.text('Installation in progress'), findsOneWidget);
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ops.actions, isEmpty);
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Installation completed'));
      await tester.pumpAndSettle();
      expect(ops.actions, [VmAction.confirmInstallation]);
      expect(find.text('Installation in progress'), findsNothing);
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();
      expect(ops.actions, [VmAction.confirmInstallation, VmAction.start]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
