import 'dart:io';

import 'package:path/path.dart' as p;

class WindowsX64Firmware {
  const WindowsX64Firmware(this.code, this.variables);
  final String code, variables;

  Future<void> validate() async {
    for (final entry in {code: 3653632, variables: 540672}.entries) {
      if (await FileSystemEntity.type(entry.key, followLinks: false) !=
              FileSystemEntityType.file ||
          await File(entry.key).length() != entry.value) {
        throw const FormatException(
          'Compatible Windows UEFI firmware is missing. Prepare the Intel Windows firmware before creating a VM; see the Windows x64 setup guide.',
        );
      }
    }
  }

  static Future<WindowsX64Firmware> locate() async {
    final home = Platform.environment['HOME'];
    if (home == null) {
      throw const FormatException('Home directory is unavailable.');
    }
    final root = p.join(
      home,
      '.local',
      'share',
      'quickgui',
      'firmware',
      'windows-x64',
    );
    final result = WindowsX64Firmware(
      p.join(root, 'OVMF_CODE_4M.secboot.fd'),
      p.join(root, 'OVMF_VARS_4M.ms.fd'),
    );
    await result.validate();
    return result;
  }
}

/// Quickemu 4.9.9 clears the configured EFI_CODE inside vm_boot. Refuse that
/// known backend until the narrowly scoped, backed-up compatibility fix is applied.
Future<void> validateWindowsFirmwareBackend(String? executable) async {
  if (executable == null) {
    throw const FormatException('Quickemu is unavailable.');
  }
  final source = await File(executable).readAsString();
  if (source.contains(
    '    DISPLAY_RENDER=""\n    EFI_CODE=""\n    EFI_VARS=""',
  )) {
    throw const FormatException(
      'This Quickemu version ignores the configured Windows UEFI firmware. Apply the Windows x64 backend setup fix before starting installation.',
    );
  }
}
