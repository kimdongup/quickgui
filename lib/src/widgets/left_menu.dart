import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:provider/provider.dart';
import 'package:quickgui/src/supported_locales.dart';

import '../globals.dart';
import '../mixins/app_version.dart';
import '../mixins/preferences_mixin.dart';
import '../model/app_settings.dart';

class LeftMenu extends StatefulWidget {
  const LeftMenu({super.key});

  @override
  State<LeftMenu> createState() => _LeftMenuState();
}

class _LeftMenuState extends State<LeftMenu> with PreferencesMixin {
  List<DropdownMenuItem<String>> _dropdownMenuItems = [];
  late String currentLocale;
  late final Future<String> _quickemuVersion;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quickemuVersion = fetchQuickemuVersion();
    _dropdownMenuItems = supportedLocales
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList();
  }

  @override
  void didChangeDependencies() {
    var appSettings = context.read<AppSettings>();
    currentLocale = appSettings.activeLocale;
    if (!supportedLocales.contains(currentLocale)) {
      currentLocale = currentLocale.split("_")[0];
      if (!supportedLocales.contains(currentLocale)) {
        currentLocale = "en";
      }
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    var version = AppVersion.packageInfo?.version ?? '';

    return Consumer<AppSettings>(
      builder: (context, appSettings, _) {
        return Drawer(
          child: ListView(
            children: [
              Padding(
                // Minimal bottom padding
                padding: const EdgeInsets.only(bottom: 0)
                    .add(const EdgeInsets.symmetric(horizontal: 16)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    "Quickgui $version",
                    style: const TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              FutureBuilder<String>(
                future: _quickemuVersion,
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator(); // or some other widget while waiting
                      } else {
                        String poweredByText =
                            "${context.t('Powered by')} Quickemu";
                        if (snapshot.hasData) {
                          poweredByText += " ${snapshot.data}";
                        }
                        return Padding(
                          // Minimal top padding
                          padding: const EdgeInsets.only(top: 0)
                              .add(const EdgeInsets.symmetric(horizontal: 16)),
                          child: Text(
                            poweredByText,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }
                    },
              ),
              Container(height: 4.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Flexible(child: Text(context.t('Use dark mode'))),
                    Expanded(child: Container()),
                    Switch(
                      value:
                          Theme.of(context).colorScheme.brightness ==
                          Brightness.dark,
                      activeThumbColor: Colors.black26,
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveThumbColor: Colors.grey[500],
                      inactiveTrackColor: Colors.grey[300],

                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              prefThemeMode,
                              value,
                              () => appSettings.useDarkMode = value,
                            ),
                      // activeColor: Colors.white,
                      // activeTrackColor: Colors.black26,
                      // inactiveThumbColor:
                      //     Theme.of(context).colorScheme.onPrimary,
                      // inactiveTrackColor: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              Container(height: 4.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(context.t('Language')),
                    Expanded(child: Container()),
                    DropdownButton<String>(
                      value: currentLocale,
                      items: _dropdownMenuItems,
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              _save(prefCurrentLocale, value, () {
                                currentLocale = value;
                                appSettings.activeLocale = value;
                              });
                            },
                    ),
                  ],
                ),
              ),
              Container(height: 32.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: const <TextSpan>[
                          TextSpan(
                            text: 'Authors\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: 'Yannick Mauray\n'),
                          TextSpan(text: 'Mark Johnson\n'),
                          TextSpan(text: 'Martin Wimpress\n'),
                        ],
                      ),
                    ),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: const <TextSpan>[
                          TextSpan(text: '© 2021 - 2024\n'),
                          TextSpan(
                            text: 'Quickemu Project\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(String key, Object value, VoidCallback apply) async {
    setState(() => _saving = true);
    try {
      await savePreference(key, value);
      if (mounted) setState(apply);
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Error')),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('OK')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
