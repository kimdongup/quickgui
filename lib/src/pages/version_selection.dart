import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:tuple/tuple.dart';

import '../model/operating_system.dart';
import '../model/option.dart';
import '../model/version.dart';
import '../widgets/selection_list.dart';
import 'option_selection.dart';

class VersionSelection extends StatelessWidget {
  const VersionSelection({required this.operatingSystem, super.key});
  final OperatingSystem operatingSystem;
  @override
  Widget build(BuildContext context) => SelectionList<Version>(
    title: context.t('Select version for {0}', args: [operatingSystem.name]),
    searchHint: context.t('Search version'),
    items: operatingSystem.versions,
    label: (version) => version.version,
    onSelect: (version) async {
      final option = version.options.length > 1
          ? await Navigator.of(context).push<Option>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (context) => OptionSelection(version),
              ),
            )
          : version.options.firstOrNull ?? Option('', 'curl');
      if (option != null && context.mounted) {
        Navigator.of(context).pop(Tuple2<Version, Option?>(version, option));
      }
    },
  );
}
