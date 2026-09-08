import 'package:flutter/material.dart';

import '../workspace_picker.dart';
import 'home_page_button_group.dart';

class DownloaderMenu extends StatefulWidget {
  const DownloaderMenu({super.key});
  @override
  State<DownloaderMenu> createState() => _DownloaderMenuState();
}

class _DownloaderMenuState extends State<DownloaderMenu> {
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        children: [
          WorkspacePicker(onChanged: () => setState(() {})),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: HomePageButtonGroup(),
          ),
        ],
      ),
    ),
  );
}
