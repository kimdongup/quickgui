import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../../main.dart' show loadOperatingSystems;
import '../model/operating_system.dart';
import '../model/osicons.dart';
import '../services/guest_catalog.dart';
import '../widgets/selection_list.dart';

class OperatingSystemSelection extends StatefulWidget {
  const OperatingSystemSelection({this.load, super.key});
  final Future<List<OperatingSystem>> Function()? load;
  @override
  State<OperatingSystemSelection> createState() =>
      _OperatingSystemSelectionState();
}

class _OperatingSystemSelectionState extends State<OperatingSystemSelection> {
  late Future<List<OperatingSystem>> _catalog;
  @override
  void initState() {
    super.initState();
    _catalog = (widget.load ?? loadOperatingSystems)();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OperatingSystem>>(
    future: _catalog,
    builder: (context, snapshot) => SelectionList<OperatingSystem>(
      title: context.t('Select operating system'),
      searchHint: context.t('Search operating system'),
      items: snapshot.hasData && snapshot.data!.isNotEmpty
          ? withArmMedia(snapshot.data!)
          : [],
      label: (os) => os.displayName,
      subtitle: (os) => os.armMedia == null
          ? null
          : Text(
              context.t(
                os.armMedia == ArmMedia.macos
                    ? 'Download IPSW or install an Apple Silicon VM.'
                    : 'Installation image only; VM setup is separate.',
              ),
            ),
      onSelect: (os) => Navigator.of(context).pop(os),
      icon: (os) => osIcons.containsKey(os.code)
          ? SvgPicture.asset(osIcons[os.code]!, width: 32, height: 32)
          : const Icon(Icons.computer, size: 32),
      status: snapshot.hasError
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText('${snapshot.error}'),
                    TextButton(
                      onPressed: () => setState(() {
                        _catalog = (widget.load ?? loadOperatingSystems)();
                      }),
                      child: Text(context.t('Retry')),
                    ),
                  ],
                ),
              ),
            )
          : snapshot.connectionState != ConnectionState.done
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.t('Loading available downloads')),
                ],
              ),
            )
          : null,
    ),
  );
}
