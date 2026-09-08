import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../globals.dart';

class WorkspacePicker extends StatelessWidget {
  const WorkspacePicker({this.onChanged, super.key});
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '${context.t('Directory where the machines are stored')}:',
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: () async {
              try {
                final path = await FilePicker.getDirectoryPath(
                  initialDirectory: workingDirectory,
                );
                if (path == null) return;
                await gWorkspace!.select(path);
                if (context.mounted) onChanged?.call();
              } catch (e) {
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(context.t('Error')),
                    content: SelectableText('$e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.t('OK')),
                      ),
                    ],
                  ),
                );
              }
            },
            child: Tooltip(
              message: workingDirectory,
              child: Text(
                workingDirectory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
