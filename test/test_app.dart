import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

class TestTranslations extends LocalizationsDelegate<GettextLocalizations> {
  const TestTranslations();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<GettextLocalizations> load(Locale locale) => SynchronousFuture(
    GettextLocalizations.fromPO(File('assets/i18n/en.po').readAsStringSync()),
  );
  @override
  bool shouldReload(covariant TestTranslations old) => false;
}

Widget testApp(Widget child) => MaterialApp(
  theme: ThemeData(
    fontFamily: 'Roboto',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.pink),
  ),
  locale: const Locale('en'),
  localizationsDelegates: const [TestTranslations()],
  home: child,
);
