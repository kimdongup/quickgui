import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'command_runner.dart';
import 'toolchain.dart';

class BackendSettings {
  const BackendSettings({
    this.quickemu = '',
    this.quickget = '',
    this.display = '',
    this.sound = '',
    this.architecture = '',
  });
  final String quickemu, quickget, display, sound, architecture;
  static const key = 'personal.backendSettings';
  static Future<BackendSettings> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return const BackendSettings();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return BackendSettings(
      quickemu: json['quickemu'] as String? ?? '',
      quickget: json['quickget'] as String? ?? '',
      display: json['display'] as String? ?? '',
      sound: json['sound'] as String? ?? '',
      architecture: json['architecture'] as String? ?? '',
    );
  }

  Future<void> save() async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'quickemu': quickemu,
        'quickget': quickget,
        'display': display,
        'sound': sound,
        'architecture': architecture,
      }),
    )) {
      throw StateError('Cannot save backend settings');
    }
  }

  List<String> get startArguments => [
    if (display.isNotEmpty) ...['--display', display],
    if (sound.isNotEmpty) ...['--sound-duplex', sound],
  ];
  List<String> get downloadArguments => [
    if (architecture.isNotEmpty) ...['--arch', architecture],
  ];

  Future<BackendCapabilities> check(
    Toolchain tools,
    CommandRunner runner,
  ) async {
    final emu = tools.find(quickemu.isEmpty ? 'quickemu' : quickemu);
    final get = tools.find(quickget.isEmpty ? 'quickget' : quickget);
    if (emu == null || get == null) {
      throw StateError('Choose executable quickemu and quickget files');
    }
    Future<String> help(String executable) async {
      final result = await runner.run(
        executable,
        ['--help'],
        directory: Directory.systemTemp.path,
        environment: tools.environment,
      );
      result.requireSuccess();
      return result.stdout;
    }

    return BackendCapabilities(await help(emu), await help(get));
  }
}

class BackendCapabilities {
  const BackendCapabilities(this.quickemuHelp, this.quickgetHelp);
  final String quickemuHelp, quickgetHelp;
  List<String> get displays => _choices(quickemuHelp, '--display', [
    'gtk',
    'sdl',
    'cocoa',
    'none',
    'spice',
    'spice-app',
  ]);
  List<String> get sounds => _choices(quickemuHelp, '--sound-duplex', [
    'hda-micro',
    'hda-duplex',
    'hda-output',
  ]);
  List<String> get architectures =>
      _choices(quickgetHelp, '--arch', ['amd64', 'arm64']);
  List<String> _choices(String help, String flag, List<String> values) {
    final line = help
        .split('\n')
        .where((line) => line.trimLeft().startsWith('$flag '))
        .join(' ');
    return values
        .where(
          (value) => RegExp(
            '(?<![a-zA-Z0-9_-])${RegExp.escape(value)}(?![a-zA-Z0-9_-])',
          ).hasMatch(line),
        )
        .toList();
  }

  void validate(BackendSettings settings) {
    if ((settings.display.isNotEmpty && !displays.contains(settings.display)) ||
        (settings.sound.isNotEmpty && !sounds.contains(settings.sound)) ||
        (settings.architecture.isNotEmpty &&
            !architectures.contains(settings.architecture))) {
      throw StateError('The selected backend does not support these overrides');
    }
  }
}
