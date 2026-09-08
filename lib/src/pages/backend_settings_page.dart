import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../globals.dart';
import '../services/backend_settings.dart';

class BackendSettingsPage extends StatefulWidget {
  const BackendSettingsPage({super.key});
  @override
  State<BackendSettingsPage> createState() => _BackendSettingsPageState();
}

class _BackendSettingsPageState extends State<BackendSettingsPage> {
  late final TextEditingController _emu, _get;
  late String _display, _sound, _architecture;
  BackendCapabilities? _capabilities;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final settings = gBackendSettings;
    _emu = TextEditingController(text: settings.quickemu);
    _get = TextEditingController(text: settings.quickget);
    _display = settings.display;
    _sound = settings.sound;
    _architecture = settings.architecture;
  }

  BackendSettings get _settings => BackendSettings(
    quickemu: _emu.text.trim(),
    quickget: _get.text.trim(),
    display: _display,
    sound: _sound,
    architecture: _architecture,
  );
  Future<void> _check({bool save = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = _settings;
      final capabilities = await settings.check(gToolchain, gRunner);
      if (!mounted) return;
      setState(() => _capabilities = capabilities);
      if (save) {
        capabilities.validate(settings);
        await settings.save();
        gBackendSettings = settings;
        configureProcessEnvironment();
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emu.dispose();
    _get.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('Advanced settings'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.t('Leave paths empty to discover tools automatically.')),
        for (final entry in {'quickemu': _emu, 'quickget': _get}.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: entry.value,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: '${entry.key} ${context.t('Executable path')}',
              ),
              onChanged: (_) => setState(() => _capabilities = null),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : _check,
          child: Text(context.t('Check backends')),
        ),
        _choice(
          context.t('Display'),
          _display,
          _capabilities?.displays ?? [],
          (value) => _display = value,
        ),
        _choice(
          context.t('Sound'),
          _sound,
          _capabilities?.sounds ?? [],
          (value) => _sound = value,
        ),
        _choice(
          context.t('Download architecture'),
          _architecture,
          _capabilities?.architectures ?? [],
          (value) => _architecture = value,
        ),
        Text(
          context.t(
            'Existing machines keep the architecture in their configuration.',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(_error!),
          ),
        if (_busy) const LinearProgressIndicator(),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _emu.clear();
                        _get.clear();
                        _display = '';
                        _sound = '';
                        _architecture = '';
                        _capabilities = null;
                      });
                    },
              child: Text(context.t('Use defaults')),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _busy ? null : () => _check(save: true),
              child: Text(context.t('Save')),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _choice(
    String label,
    String value,
    List<String> supported,
    void Function(String) apply,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<String>(
          value: value,
          items: {'', value, ...supported}
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(value.isEmpty ? context.t('Default') : value),
                ),
              )
              .toList(),
          onChanged: _busy || _capabilities == null
              ? null
              : (value) {
                  if (value != null) setState(() => apply(value));
                },
        ),
      ],
    ),
  );
}
