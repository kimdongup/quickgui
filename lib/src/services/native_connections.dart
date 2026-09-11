import 'dart:io';

import 'package:path/path.dart' as p;

import 'connections.dart';
import 'native_vm.dart';
import 'toolchain.dart';

Future<NativeVmRecord> currentNativeConnection(
  NativeVmRecord selected,
  NativeVmService service,
) async {
  final current = await service.status(selected.path);
  if (!selected.hasSsh ||
      !current.hasSsh ||
      current.connectionSession != selected.connectionSession ||
      current.sshPort != selected.sshPort) {
    throw StateError('VM connection changed; refresh and try again');
  }
  return current;
}

Future<List<String>> nativeSpiceArguments(
  NativeVmRecord selected,
  NativeVmService service,
) async {
  final current = await currentNativeConnection(selected, service);
  final socket = current.spiceSocket;
  if (socket == null ||
      socket != selected.spiceSocket ||
      !p.isAbsolute(socket) ||
      socket.contains('\u0000')) {
    throw StateError('SPICE display is unavailable; refresh and try again');
  }
  return ['--uri=spice+unix://$socket'];
}

Future<int> nativeSshPort(
  NativeVmRecord selected,
  NativeVmService service,
) async {
  final current = await currentNativeConnection(selected, service);
  if (!await detectSsh(current.sshPort!)) {
    throw StateError(
      'Windows SSH server is not ready. Check OpenSSH Server and the guest firewall.',
    );
  }
  return (await currentNativeConnection(selected, service)).sshPort!;
}

String? nativeSpiceViewer(Toolchain tools) {
  final home = tools.environment['HOME'];
  if (Platform.isMacOS && home != null) {
    final bundled = tools.find(
      p.join(
        home,
        'Library',
        'Application Support',
        'Quickgui',
        'Backends',
        'windows-arm-spice',
        'SPICE Viewer.app',
        'Contents',
        'MacOS',
        'spicy',
      ),
    );
    if (bundled != null) return bundled;
  }
  return tools.find('spicy');
}
