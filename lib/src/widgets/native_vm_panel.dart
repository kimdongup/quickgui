import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../pages/native_vm_create.dart';
import '../services/native_vm.dart';
import 'native_vm_controls.dart';

/// Independent of Quickemu availability and its .conf repository.
class NativeVmPanel extends StatefulWidget {
  const NativeVmPanel({
    required this.directory,
    this.service = const NativeVmService(),
    super.key,
  });
  final String directory;
  final NativeVmService service;
  @override
  State<NativeVmPanel> createState() => _NativeVmPanelState();
}

class _NativeVmPanelState extends State<NativeVmPanel> {
  bool _supported = false, _refreshing = false;
  List<NativeVmRecord> _vms = [];
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final supported = await widget.service.supported();
      if (!mounted) return;
      setState(() => _supported = supported);
      if (supported) {
        await _refresh();
        if (mounted) {
          _timer = Timer.periodic(
            const Duration(seconds: 2),
            (_) => unawaited(_refresh()),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = nativeVmError(e));
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final directory = widget.directory;
    try {
      final vms = await widget.service.list(directory);
      if (mounted && directory == widget.directory) {
        setState(() {
          _vms = vms;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && directory == widget.directory) {
        setState(() {
          _vms = [];
          _error = nativeVmError(e);
        });
      }
    } finally {
      _refreshing = false;
      if (mounted && directory != widget.directory) unawaited(_refresh());
    }
  }

  @override
  void didUpdateWidget(covariant NativeVmPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      _vms = [];
      _error = null;
      if (_supported) unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported && _error == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_supported) ...[
          Text(
            widget.service.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NativeVmCreate(
                      directory: widget.directory,
                      service: widget.service,
                    ),
                  ),
                );
                if (mounted) await _refresh();
              },
              icon: const Icon(Icons.add),
              label: Text(context.t(widget.service.createLabel)),
            ),
          ),
        ],
        if (_error != null) ...[
          SelectableText(_error!),
          TextButton(
            onPressed: _supported ? _refresh : _initialize,
            child: Text(context.t('Retry')),
          ),
        ],
        for (final vm in _vms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vm.name, style: Theme.of(context).textTheme.titleMedium),
                if (vm.version.isNotEmpty)
                  Text('${widget.service.title} ${vm.version}'),
                SelectableText(
                  vm.path,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                NativeVmControls(
                  key: ValueKey(vm.path),
                  vm: vm,
                  service: widget.service,
                  onChanged: _refresh,
                ),
              ],
            ),
          ),
        const Divider(thickness: 2),
      ],
    );
  }
}
