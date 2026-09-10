import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import '../services/native_vm.dart';
import '../widgets/native_vm_controls.dart';

class NativeVmCreate extends StatefulWidget {
  const NativeVmCreate({
    required this.directory,
    this.imagePath,
    this.service = const NativeVmService(),
    super.key,
  });
  final String directory;
  final String? imagePath;
  final NativeVmService service;
  @override
  State<NativeVmCreate> createState() => _NativeVmCreateState();
}

class _NativeVmCreateState extends State<NativeVmCreate> {
  final _name = TextEditingController(text: 'macOS Apple Silicon');
  final _form = GlobalKey<FormState>();
  String? _imagePath, _error;
  NativeInstallationImage? _image;
  NativeVmRecord? _vm;
  int _cpus = 2, _memory = 4, _disk = 64;
  bool _loading = false, _refreshing = false;
  Timer? _timer;
  bool get _windows => widget.service.windows;

  @override
  void initState() {
    super.initState();
    if (_windows) _name.text = 'Windows 11 ARM64';
    if (widget.imagePath != null) unawaited(_inspect(widget.imagePath!));
  }

  Future<void> _inspect(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _image = null;
      _imagePath = path;
    });
    try {
      final image = await widget.service.inspectImage(path);
      if (image.minimumCPU > image.maximumCPU ||
          image.minimumMemoryGiB > image.maximumMemoryGiB) {
        throw StateError(
          'This Mac does not have enough resources for this installation image.',
        );
      }
      if (mounted) {
        setState(() {
          _image = image;
          _cpus = 2.clamp(image.minimumCPU, image.maximumCPU);
          _memory = 4.clamp(image.minimumMemoryGiB, image.maximumMemoryGiB);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = nativeVmError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [_windows ? 'iso' : 'ipsw'],
        initialDirectory: p.join(widget.directory, 'Install Media'),
      );
      final path = files.isEmpty ? null : files.single.path;
      if (path != null && mounted) await _inspect(path);
    } catch (e) {
      if (mounted) setState(() => _error = nativeVmError(e));
    }
  }

  Future<void> _create() async {
    if (_loading ||
        _vm != null ||
        _image == null ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vm = await widget.service.create(
        directory: widget.directory,
        name: _name.text.trim(),
        imagePath: _imagePath!,
        cpus: _cpus,
        memoryGiB: _memory,
        diskGiB: _disk,
      );
      if (mounted) {
        setState(() => _vm = vm);
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_refresh()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = nativeVmError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || _vm == null) return;
    _refreshing = true;
    try {
      final vm = await widget.service.status(_vm!.path);
      if (mounted) {
        setState(() {
          _vm = vm;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = nativeVmError(e));
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Widget _resource(
    String label,
    int value,
    List<int> choices,
    ValueChanged<int> change,
  ) => SizedBox(
    width: 160,
    child: DropdownButtonFormField<int>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      decoration: InputDecoration(labelText: context.t(label)),
      items: [
        for (final choice in choices)
          DropdownMenuItem(value: choice, child: Text('$choice')),
      ],
      onChanged: _loading ? null : (value) => setState(() => change(value!)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = _image, vm = _vm;
    return Scaffold(
      appBar: AppBar(title: Text(context.t(widget.service.createLabel))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm == null) ...[
                Text(
                  context.t(
                    _windows
                        ? 'Install Windows ARM64 from a downloaded ISO. The original image is kept.'
                        : 'Install macOS from a downloaded IPSW. The original image is kept.',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pick,
                  icon: const Icon(Icons.file_open),
                  label: Text(
                    context.t(_windows ? 'Choose ARM64 ISO' : 'Choose IPSW'),
                  ),
                ),
                if (_imagePath != null) SelectableText(_imagePath!),
                if (image != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${widget.service.title} ${image.version} (${image.build})',
                  ),
                  TextFormField(
                    controller: _name,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      labelText: context.t('VM name'),
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty ||
                          name == '.' ||
                          name == '..' ||
                          name.length > 60 ||
                          RegExp(r'[/\\:\x00-\x1f\x7f]').hasMatch(name)) {
                        return context.t(
                          'Enter a short VM name without slashes or colons.',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _resource('CPU cores', _cpus, [
                        for (
                          var i = image.minimumCPU;
                          i <= image.maximumCPU;
                          i++
                        )
                          i,
                      ], (v) => _cpus = v),
                      _resource('Memory (GiB)', _memory, [
                        for (
                          var i = image.minimumMemoryGiB;
                          i <= image.maximumMemoryGiB;
                          i++
                        )
                          i,
                      ], (v) => _memory = v),
                      _resource('Disk (GiB)', _disk, [
                        64,
                        128,
                        256,
                      ], (v) => _disk = v),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.t(
                      'The disk grows as it is used. Keep at least 32 GiB free to begin installation and allow more space as the guest grows.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(widget.directory),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _create,
                    child: Text(context.t('Create and install')),
                  ),
                ],
              ] else ...[
                Text(vm.name, style: Theme.of(context).textTheme.titleLarge),
                SelectableText(vm.path),
                const SizedBox(height: 16),
                NativeVmControls(
                  vm: vm,
                  service: widget.service,
                  onChanged: _refresh,
                ),
                const SizedBox(height: 16),
                Text(
                  context.t(
                    _windows
                        ? 'Follow Windows setup in the VM display. If asked to boot from the installation media, press a key. After reaching the desktop and shutting down, choose Installation completed to boot from disk next time.'
                        : 'Installation continues while Quickgui is open. You can follow progress in Manager. After installation, use Run to finish macOS setup.',
                  ),
                ),
                Text(
                  context.t(
                    _windows
                        ? 'Shut down from Windows or Manager before quitting Quickgui. Closing the QEMU window stops the VM.'
                        : 'Closing the VM display keeps the VM running. Shut down from the guest or Manager before quitting Quickgui.',
                  ),
                ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null) SelectableText(_error!),
              TextButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: Text(context.t('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
