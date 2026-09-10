import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../services/native_storage.dart';
import '../services/native_vm.dart';
import '../widgets/storage_delete_dialog.dart';

class InstallationMedia extends StatefulWidget {
  const InstallationMedia({
    required this.directory,
    this.service = const NativeStorageService(),
    super.key,
  });
  final String directory;
  final NativeStorageService service;
  @override
  State<InstallationMedia> createState() => _InstallationMediaState();
}

class _InstallationMediaState extends State<InstallationMedia> {
  List<InstallationFile> _files = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await widget.service.listMedia(widget.directory);
      if (mounted) setState(() => _files = files);
    } catch (error) {
      if (mounted) setState(() => _error = nativeVmError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso', 'ipsw'],
      );
      if (files.isNotEmpty && files.single.path != null) {
        await widget.service.addMedia(files.single.path!);
        final updated = await widget.service.listMedia(widget.directory);
        if (mounted) setState(() => _files = updated);
      }
    } catch (error) {
      if (mounted) setState(() => _error = nativeVmError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(InstallationFile file) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.service.preview(
        path: file.path,
        directory: widget.directory,
        isVM: false,
      );
      if (!mounted || !await confirmStorageDeletion(context, preview)) return;
      await widget.service.delete(preview, directory: widget.directory);
      final files = await widget.service.listMedia(widget.directory);
      if (mounted) setState(() => _files = files);
    } catch (error) {
      if (mounted) setState(() => _error = nativeVmError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('Installation files'))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t(
              'ISO and IPSW files from this workspace and files selected in Quickgui. Use Add installation file for Downloads or another folder.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.file_open),
                label: Text(context.t('Add installation file')),
              ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: Text(context.t('Refresh')),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) SelectableText(_error!),
          if (!_busy && _files.isEmpty && _error == null)
            Text(context.t('No installation files found.')),
          for (final file in _files)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${file.kind} · ${context.t('Size on disk')}: ${storageSize(file.bytes)}',
                    ),
                    SelectableText(file.path),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _delete(file),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.t('Delete installation file')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
