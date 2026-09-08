import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/src/globals.dart';
import 'package:quickgui/src/pages/manager.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/connections.dart';
import 'package:quickgui/src/services/toolchain.dart';
import 'package:quickgui/src/services/vm_service.dart';

import 'test_app.dart';

class VmProcessRunner extends CommandRunner {
  String process = '';
  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String directory,
    required Map<String, String> environment,
    Duration timeout = const Duration(seconds: 30),
    int outputLimit = 65536,
  }) async => CommandResult(process.isEmpty ? 1 : 0, process, '');
}

class SocketRepository extends VmRepository {
  bool running = true;
  VmRecord get record => VmRecord(
    configPath: '/test/mac.conf',
    content: 'fixture',
    state: running ? VmState.running : VmState.stopped,
    pid: running ? 1234 : null,
    spiceSocketPath: running ? '/test/mac.sock' : null,
  );
  @override
  Future<List<VmRecord>> list(String directory) async => [record];
  @override
  Future<VmRecord?> inspect(String configPath) async => record;
}

class ViewerToolchain extends Toolchain {
  @override
  String? find(String name) => name == 'spicy' ? '/unused/spicy' : null;
}

void main() {
  late Directory tmp, stateDirectory;
  late File config, ports, pidFile;
  late VmProcessRunner runner;
  late VmRepository repository;
  setUp(() async {
    // Keep below macOS's Unix socket path length limit.
    tmp = await Directory.systemTemp.createTemp('qgs-');
    stateDirectory = await Directory('${tmp.path}/vm').create();
    config = await File('${tmp.path}/vm.conf')
        .writeAsString('guest_os="linux"\ndisk_img="vm/disk.qcow2"\n');
    ports = File('${stateDirectory.path}/vm.ports');
    pidFile = await File('${stateDirectory.path}/vm.pid').writeAsString('1234');
    runner = VmProcessRunner()
      ..process = 'qemu-system-x86_64 -pidfile ${pidFile.path} -m 1024';
    repository = VmRepository(runner: runner);
  });
  tearDown(() async => tmp.delete(recursive: true));

  test(
    'local Unix SPICE keeps literal spaces, commas, percent and Unicode',
    () async {
      final socketPath = '${stateDirectory.path}/a ,%한.sock';
      final server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      try {
        for (final path in [
          p.relative(socketPath, from: tmp.path),
          socketPath,
        ]) {
          await ports.writeAsString('ssh,22220\nunix,$path\n');
          final vm = (await repository.inspect(config.path))!;
          expect(vm.state, VmState.running);
          expect(vm.hasSpice, isTrue);
          expect(vm.spiceSocketPath, socketPath);
          expect(vm.spicePort, isNull);
          expect(vm.sshPort, 22220);
          expect(await spiceArguments(vm, repository: repository), [
            '--uri=spice+unix://$socketPath',
          ]);
        }
        final selected = (await repository.inspect(config.path))!;
        await File(socketPath).delete();
        await expectLater(
          spiceArguments(selected, repository: repository),
          throwsStateError,
        );
      } finally {
        await server.close();
      }
    },
  );

  test(
    'missing sockets and ordinary files never become display endpoints',
    () async {
      final ordinary = await File('${stateDirectory.path}/ordinary')
          .writeAsString('x');
      for (final path in ['', '${tmp.path}/missing', ordinary.path, tmp.path]) {
        await ports.writeAsString('unix,$path\nspice,65536\n');
        expect((await repository.inspect(config.path))!.hasSpice, isFalse);
      }
    },
  );

  test(
    'TCP remains supported and connection rechecks PID, config and state',
    () async {
      await ports.writeAsString('ssh,22220\nspice,5930\n');
      final selected = (await repository.inspect(config.path))!;
      expect(await spiceArguments(selected, repository: repository), [
        '-h',
        '127.0.0.1',
        '-p',
        '5930',
      ]);
      await ports.writeAsString('spice,5931\n');
      expect(
        (await spiceArguments(selected, repository: repository)).last,
        '5931',
      );
      await pidFile.writeAsString('5678');
      await expectLater(
        spiceArguments(selected, repository: repository),
        throwsStateError,
      );
      await pidFile.writeAsString('1234');
      await config.writeAsString('${selected.content}# changed\n');
      await expectLater(
        spiceArguments(selected, repository: repository),
        throwsStateError,
      );
      await config.writeAsString(selected.content);
      runner.process = '/usr/bin/unrelated';
      expect((await repository.inspect(config.path))!.hasSpice, isFalse);
      await expectLater(
        spiceArguments(selected, repository: repository),
        throwsStateError,
      );
      runner.process = '';
      expect((await repository.inspect(config.path))!.hasSpice, isFalse);
      await expectLater(
        spiceArguments(selected, repository: repository),
        throwsStateError,
      );
    },
  );

  testWidgets('Unix-only VM has a viewer button and rechecks before launch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(692, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = gToolchain;
    gToolchain = ViewerToolchain();
    addTearDown(() => gToolchain = original);
    final repository = SocketRepository();
    final ops = VmOperations(repository: repository);
    addTearDown(ops.dispose);
    await tester.pumpWidget(testApp(Manager(operations: ops)));
    await tester.pumpAndSettle();
    expect(find.text('SPICE socket'), findsOneWidget);
    final button = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == 'Connect display with SPICE',
    );
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    repository.running = false;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('VM state changed; refresh and try again'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
