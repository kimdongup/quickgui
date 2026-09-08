import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'globals.dart';
import 'model/app_settings.dart';
import 'pages/main_page.dart';
import 'pages/debget_not_found_page.dart';
import 'supported_locales.dart';

class App extends StatefulWidget {
  const App({required this.initialize, super.key});
  final Future<void> Function() initialize;
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _ready = false);
    try {
      await widget.initialize();
      if (!mounted) return;
      final settings = context.read<AppSettings>();
      settings.setActiveLocaleSilently(Platform.localeName);
      try {
        final prefs = await SharedPreferences.getInstance();
        settings.setActiveLocaleSilently(
          prefs.get(prefCurrentLocale) is String
              ? prefs.getString(prefCurrentLocale)!
              : Platform.localeName,
        );
        settings.useDarkModeSilently = prefs.get(prefThemeMode) is bool
            ? prefs.getBool(prefThemeMode)!
            : false;
      } catch (error) {
        gStartupError = 'Unable to read settings: $error';
      }
    } catch (error) {
      gStartupError = '$error';
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final ready =
        gStartupError == null &&
        gQuickgetExecutable != null &&
        gQuickemuExecutable != null &&
        (gWorkspace?.available ?? false);
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.pink,
          backgroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.pink,
          backgroundColor: const Color(0xFF616161),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: settings.themeMode,
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ready
          ? const MainPage()
          : DebgetNotFoundPage(
              onRetry: _initialize,
              onWorkspaceChanged: () => setState(() {}),
            ),
      supportedLocales: supportedLocales.map(
        (s) => s.contains('_')
            ? Locale(s.split('_')[0], s.split('_')[1])
            : Locale(s),
      ),
      localizationsDelegates: [
        GettextLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
        GlobalWidgetsLocalizations.delegate,
      ],
      locale: Locale(settings.languageCode ?? 'en', settings.countryCode),
    );
  }
}
