import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/backend_settings.dart';
import 'package:quickgui/src/services/vm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'defaults leave commands unchanged; overrides persist and reset together',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect((await BackendSettings.load()).startArguments, isEmpty);
      expect((await BackendSettings.load()).downloadArguments, isEmpty);
      const settings = BackendSettings(
        quickemu: '/my tools/quickemu',
        display: 'cocoa',
        sound: 'hda-output',
        architecture: 'arm64',
      );
      await settings.save();
      final loaded = await BackendSettings.load();
      expect(loaded.quickemu, settings.quickemu);
      expect(loaded.startArguments, [
        '--display',
        'cocoa',
        '--sound-duplex',
        'hda-output',
      ]);
      expect(loaded.downloadArguments, ['--arch', 'arm64']);
      await const BackendSettings().save();
      expect((await BackendSettings.load()).downloadArguments, isEmpty);
      expect((await BackendSettings.load()).quickemu, isEmpty);
    },
  );
  test('unsupported options are rejected and cannot be inferred from unrelated help text', () {
    const caps = BackendCapabilities(
      "  --display : 'cocoa', 'none'\n  --sound-duplex : 'hda-output'\nspice is not compiled in",
      ' --arch <arch> : arm64, amd64',
    );
    caps.validate(
      const BackendSettings(display: 'cocoa', architecture: 'arm64'),
    );
    expect(caps.displays, ['cocoa', 'none']);
    expect(
      () => caps.validate(const BackendSettings(display: 'spice')),
      throwsStateError,
    );
    expect(
      () => const BackendCapabilities(
        '',
        '',
      ).validate(const BackendSettings(architecture: 'arm64')),
      throwsStateError,
    );
  });
  test(
    'explicit display and sound overrides take precedence over mac defaults',
    () {
      expect(
        macStartArguments(
          '',
          'cocoa hda-output',
          explicitArguments: [
            '--display',
            'none',
            '--sound-duplex',
            'hda-duplex',
          ],
        ),
        isEmpty,
      );
    },
  );
}
