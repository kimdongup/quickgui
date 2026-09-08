import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../services/vm_service.dart';
import '../services/windows_installation.dart';

class ConfigEditor extends StatefulWidget {
  const ConfigEditor({required this.vm, required this.operations, super.key});
  final VmRecord vm;
  final VmOperations operations;
  @override
  State<ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<ConfigEditor> {
  final _text = TextEditingController();
  bool _loading = true, _saving = false, _saved = false, _loaded = false;
  String? _error;
  bool get _dirty => _loaded && !_saved && _text.text != widget.vm.content;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await File(widget.vm.configPath).readAsString();
      if (content != widget.vm.content) {
        throw StateError('Config changed; close and reopen the editor');
      }
      if (mounted) {
        setState(() {
          _text.text = content;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.operations.saveConfig(widget.vm, _text.text);
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _windowsProfile() async {
    try {
      final proposed = windowsIntelProfile(_text.text, intelMac: isIntelMac);
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Windows x64 on Intel Mac')),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t(windowsIntelNotice)),
                  const SizedBox(height: 16),
                  SelectableText(
                    proposed,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Use in editor')),
            ),
          ],
        ),
      );
      if (use == true && mounted) setState(() => _text.text = proposed);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Profile unavailable')),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('OK')),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && (_loading || !_dirty),
    onPopInvokedWithResult: (popped, result) async {
      if (popped || _saving) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Discard changes?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Discard')),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        setState(() => _saved = true);
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.vm.name),
        actions: [
          if (isIntelMac && isWindowsX64(widget.vm.content))
            IconButton(
              tooltip: context.t('Windows x64 on Intel Mac'),
              icon: const Icon(Icons.build_outlined),
              onPressed: _loading || _saving || _error != null
                  ? null
                  : _windowsProfile,
            ),
          TextButton(
            onPressed: _loading || _saving || !_dirty || _error != null
                ? null
                : _save,
            child: Text(context.t('Save')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_loading || _saving) const LinearProgressIndicator(),
            if (_error != null) SelectableText(_error!),
            Expanded(
              child: TextField(
                controller: _text,
                enabled: !_loading && !_saving && _error == null,
                expands: true,
                minLines: null,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
