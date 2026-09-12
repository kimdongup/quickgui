import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_installation.dart';
import 'windows_x64_firmware.dart';

const windowsX64Page = 'https://www.microsoft.com/software-download/windows11';
const virtioIsoUrl =
    'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso';

/// A minimum size and ISO/UDF signature reject error pages and tiny partial files.
/// This does not replace the publisher's checksum or verify the guest architecture.
Future<void> validateWindowsIso(String path, {bool driver = false}) async {
  final file = File(path);
  if (!path.toLowerCase().endsWith('.iso') ||
      await FileSystemEntity.type(path) != FileSystemEntityType.file) {
    throw const FormatException('Choose a complete ISO file.');
  }
  final minimum = driver ? 32 * 1024 * 1024 : 1024 * 1024 * 1024;
  if (await file.length() < minimum) {
    throw const FormatException(
      'The ISO is too small or incomplete. An HTML download page is not installation media.',
    );
  }
  final handle = await file.open();
  try {
    await handle.setPosition(32769);
    final signature = String.fromCharCodes(await handle.read(5));
    if (!['CD001', 'BEA01', 'NSR02', 'NSR03'].contains(signature)) {
      throw const FormatException(
        'This file does not contain an ISO/UDF image.',
      );
    }
  } finally {
    await handle.close();
  }
  if (!driver && p.basename(path).toLowerCase().contains('arm64')) {
    throw const FormatException('Choose Windows x64 media, not ARM64.');
  }
}

String _literal(String value) {
  if (RegExp('["\u0024`\\\\\r\n]').hasMatch(value)) {
    throw const FormatException(
      'The image path contains unsupported config characters.',
    );
  }
  return '"$value"';
}

/// Register a new manual-install VM without invoking Quickget, creating an answer
/// file, touching an existing VM, or allocating/partitioning any guest disk.
Future<String> createWindowsX64Vm({
  required String directory,
  required String iso,
  String? driverIso,
  required bool intelProfile,
  WindowsX64Firmware? firmware,
}) async {
  if (intelProfile && firmware == null) {
    throw const FormatException(
      'The Intel profile requires Secure Boot-capable UEFI firmware.',
    );
  }
  await firmware?.validate();
  await validateWindowsIso(iso);
  if (driverIso != null) await validateWindowsIso(driverIso, driver: true);
  final image = _literal(p.absolute(iso));
  final driver = driverIso == null ? null : _literal(p.absolute(driverIso));
  final root = Directory(directory);
  if (!await root.exists()) {
    throw const FormatException('Workspace is unavailable.');
  }
  // createTemp provides a unique name even when an older VM already exists.
  final vm = await root.createTemp('windows-11-x64-');
  final config = File('${vm.path}.conf');
  try {
    var content =
        'guest_os="windows"\narch="x86_64"\nboot="efi"\ntpm="on"\nram="4G"\ncpu_cores="2"\ndisk_size="64G"\ndisk_img=${_literal(p.join(vm.path, 'disk.qcow2'))}\niso=$image\n';
    if (firmware != null) {
      content +=
          'EFI_CODE=${_literal(firmware.code)}\nEFI_EXTRA_VARS=${_literal(firmware.variables)}\n';
    }
    if (driver != null) content += 'fixed_iso=$driver\n';
    if (intelProfile) content = windowsIntelProfile(content, intelMac: true);
    await config.create(exclusive: true);
    await config.writeAsString(content, flush: true);
    return config.path;
  } catch (_) {
    // Keep any partially written config for inspection; never remove user media.
    if (!await config.exists()) await vm.delete();
    rethrow;
  }
}
