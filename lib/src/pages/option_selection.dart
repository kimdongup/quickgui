import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../model/version.dart';
import '../model/option.dart';
import '../widgets/selection_list.dart';

class OptionSelection extends StatelessWidget {
  const OptionSelection(this.version, {super.key});
  final Version version;
  @override
  Widget build(BuildContext context) => SelectionList<Option>(
    title: context.t('Select option'),
    searchHint: version.options.length <= 6 ? null : context.t('Search option'),
    items: version.options,
    label: (option) => option.option,
    onSelect: (option) => Navigator.of(context).pop(option),
  );
}
