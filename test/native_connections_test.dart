import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/native_connections.dart';
import 'package:quickgui/src/services/native_vm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native-connections');
  const service = NativeVmService(
    kind: NativeVmKind.windows,
    overrideChannel: channel,
  );
  late Map<String, Object?> current;
  setUp(() {
    current = {
      'path': '/vm',
      'name': 'Windows',
      'state': 'running',
      'sshHost': '127.0.0.1',
      'sshPort': 50827,
      'connectionSession': '/tmp/run1',
      'spiceSocket': '/tmp/run1/a ,%한.sock',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => current);
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('old native records remain valid without live endpoints', () {
    final legacy = NativeVmRecord({
      'path': '/vm',
      'name': 'Windows',
      'state': 'stopped',
    });
    expect(legacy.hasSsh, isFalse);
    expect(legacy.hasSpice, isFalse);
    expect(legacy.spiceRequested, isFalse);
  });
  test(
    'SPICE preserves literal socket paths and rechecks each connection',
    () async {
      final selected = NativeVmRecord(current);
      expect(await nativeSpiceArguments(selected, service), [
        '--uri=spice+unix:///tmp/run1/a ,%한.sock',
      ]);
      current['spiceSocket'] = '/tmp/run2/spice.sock';
      await expectLater(
        nativeSpiceArguments(selected, service),
        throwsStateError,
      );
    },
  );
  test('same SSH port after VM restart cannot reuse a stale session', () async {
    final selected = NativeVmRecord(current);
    current['connectionSession'] = '/tmp/run2';
    await expectLater(
      currentNativeConnection(selected, service),
      throwsStateError,
    );
  });
  test(
    'stopped, busy and stopping states never expose connect controls',
    () async {
      final selected = NativeVmRecord(current);
      for (final state in ['stopped', 'busy', 'stopping']) {
        current['state'] = state;
        expect(NativeVmRecord(current).hasSsh, isFalse);
        expect(NativeVmRecord(current).hasSpice, isFalse);
        await expectLater(
          currentNativeConnection(selected, service),
          throwsStateError,
        );
      }
    },
  );
  test('connection settings send only port and SPICE preference', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return null;
        });
    await service.configureConnections('/vm', port: 50827, spiceEnabled: true);
    expect(received!.method, 'configureConnections');
    expect(received!.arguments, {
      'path': '/vm',
      'port': 50827,
      'spiceEnabled': true,
    });
  });
}
