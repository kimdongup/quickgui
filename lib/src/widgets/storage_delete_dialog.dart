import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../services/native_storage.dart';

Future<bool> confirmStorageDeletion(
  BuildContext context,
  StorageDeletionPreview preview,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => StorageDeleteDialog(preview: preview),
    ) ??
    false;

class StorageDeleteDialog extends StatefulWidget {
  const StorageDeleteDialog({required this.preview, super.key});
  final StorageDeletionPreview preview;
  @override
  State<StorageDeleteDialog> createState() => _StorageDeleteDialogState();
}

class _StorageDeleteDialogState extends State<StorageDeleteDialog> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.preview;
    return AlertDialog(
      title: Text(
        context.t(item.isVM ? 'Delete VM' : 'Delete installation file'),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(
                item.isVM
                    ? 'The VM and all files inside its folder will be permanently deleted. Installation files outside the folder are kept.'
                    : 'This installation file will be permanently deleted. Installed VMs are kept.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(item.path),
            Text('${context.t('Size on disk')}: ${storageSize(item.bytes)}'),
            const SizedBox(height: 12),
            Text(context.t('Type the name to confirm deletion:')),
            SelectableText(item.name),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: context.t('Name')),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.t('Cancel')),
        ),
        TextButton(
          onPressed: _name.text == item.name && item.name.isNotEmpty
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(context.t('Delete permanently')),
        ),
      ],
    );
  }
}
