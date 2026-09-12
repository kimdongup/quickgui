import 'dart:ffi';

import 'vm_service.dart';

bool get isIntelMac => Abi.current() == Abi.macosX64;

bool isWindowsX64(String content) =>
    [
      'windows',
      'windows-server',
    ].contains(configLiteral(content, 'guest_os')) &&
    (!RegExp(r'^\s*arch\s*=', multiLine: true).hasMatch(content) ||
        ['x86_64', 'amd64'].contains(configLiteral(content, 'arch')));

const windowsIntelNotice =
    'Windows 11 profile with TPM 2.0 and SMM-protected Secure Boot on Intel Mac: '
    'TCG emulation with SMM, max CPU, 2 cores, 4 GB RAM, SATA disk, Intel network, '
    'Cocoa display and no audio. The windows-server setting selects hardware; '
    'it does not change the installed Windows edition. '
    'TPM 2.0 and Secure Boot are enabled; swtpm and prepared OVMF firmware are required. '
    'TCG is slower than HVF, which cannot provide SMM for this firmware. '
    'Only config text is changed. No answer file, installer or disk is created. '
    'Do not reattach unattended installation media to an installed disk.';

/// Deliberately accepts only flat literal configs. Rewriting arbitrary Bash can
/// change conditionals, discard custom arguments, or enable unattended setup.
String windowsIntelProfile(String content, {required bool intelMac}) {
  if (!intelMac || !isWindowsX64(content)) {
    throw StateError('This profile requires Windows x64 on an Intel Mac');
  }
  final fields = <String, String>{};
  for (final line in content.split('\n')) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final match = RegExp(r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=').firstMatch(line);
    final key = match?[1];
    if (key == null ||
        fields.containsKey(key) ||
        configLiteral(line, key) == null) {
      throw StateError(
        'This config contains shell logic or duplicate assignments. Keep its existing installation workflow and edit it manually.',
      );
    }
    fields[key] = configLiteral(line, key)!;
  }
  const legacyExtra =
      '-machine accel=hvf,hpet=on -cpu Nehalem -smp 2,sockets=1,cores=2,threads=1';
  const extra =
      '-machine accel=tcg,smm=on,hpet=on -cpu max -smp 2,sockets=1,cores=2,threads=1';
  if ((fields['extra_args'] ?? '').isNotEmpty &&
      fields['extra_args'] != legacyExtra &&
      fields['extra_args'] != extra) {
    throw StateError(
      'Custom extra_args are present. Review and edit them manually.',
    );
  }
  final settings = {
    'guest_os': 'windows-server',
    'arch': 'x86_64',
    'boot': 'efi',
    'ram': '4G',
    'cpu_cores': '2',
    'tpm': 'on',
    'secureboot': 'on',
    'display': 'cocoa',
    'gl': 'off',
    'sound_card': 'none',
    'extra_args': extra,
  };
  var result = content;
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  for (final entry in settings.entries) {
    final pattern = RegExp(
      '^[ \\t]*${entry.key}[ \\t]*=[^\\r\\n]*',
      multiLine: true,
    );
    if (fields.containsKey(entry.key)) {
      // Leave end-of-line comments intact, including comments with quotes.
      final original = pattern.firstMatch(result)![0]!;
      final assignment = RegExp(
        r'''^\s*\w+\s*=\s*(?:'[^']*'|"[^"$`\\]*"|[a-zA-Z0-9_./:+-]+)(\s*#.*)?$''',
      ).firstMatch(original);
      final comment = assignment?[1] ?? '';
      result = result.replaceFirst(
        pattern,
        '${entry.key}="${entry.value}"$comment',
      );
    } else {
      if (result.isNotEmpty && !result.endsWith('\n')) result += newline;
      result += '${entry.key}="${entry.value}"$newline';
    }
  }
  return result;
}
