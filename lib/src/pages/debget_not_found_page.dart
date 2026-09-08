import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import 'backend_settings_page.dart';

class DebgetNotFoundPage extends StatefulWidget {
  const DebgetNotFoundPage({
    required this.onRetry,
    required this.onWorkspaceChanged,
    super.key,
  });
  final Future<void> Function() onRetry;
  final VoidCallback onWorkspaceChanged;
  @override
  State<DebgetNotFoundPage> createState() => _DebgetNotFoundPageState();
}

class _DebgetNotFoundPageState extends State<DebgetNotFoundPage> {
  String? _error;
  @override
  Widget build(BuildContext context) {
    final missing = [
      if (gQuickgetExecutable == null) 'quickget',
      if (gQuickemuExecutable == null) 'quickemu',
    ];
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (missing.isNotEmpty)
                Text(
                  '${missing.join(', ')}: ${context.t('quickemu was not found in your PATH')}',
                  textAlign: TextAlign.center,
                ),
              if (gStartupError ?? gWorkspace?.error case final String error)
                SelectableText(error),
              if (_error != null) SelectableText(_error!),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const BackendSettingsPage(),
                    ),
                  );
                  if (changed == true && mounted) await widget.onRetry();
                },
                child: Text(context.t('Advanced settings')),
              ),
              ElevatedButton(
                onPressed: widget.onRetry,
                child: Text(context.t('Retry')),
              ),
              if (gWorkspace != null)
                TextButton(
                  onPressed: () async {
                    try {
                      final path = await FilePicker.getDirectoryPath();
                      if (path == null) return;
                      await gWorkspace!.select(path);
                      if (mounted) widget.onWorkspaceChanged();
                    } catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                  },
                  child: Text(context.t('Select folder')),
                ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/quickemu-project/quickemu'),
                ),
                child: const Text('github.com/quickemu-project/quickemu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
