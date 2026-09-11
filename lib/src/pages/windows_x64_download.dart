import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/operating_system.dart';
import '../services/arm_media.dart';
import '../services/windows_installation.dart';
import '../services/windows_x64_media.dart';

class WindowsX64Download extends StatefulWidget {
  const WindowsX64Download({required this.directory, super.key});
  final String directory;
  @override
  State<WindowsX64Download> createState() => _WindowsX64DownloadState();
}

class _WindowsX64DownloadState extends State<WindowsX64Download> {
  final _url = TextEditingController();
  MediaDownloadSession? _session;
  String? _iso, _driver, _error, _config;
  bool _busy = false;
  late bool _intelProfile = isIntelMac;

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(bool driver) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso'],
      );
      final path = result.firstOrNull?.path;
      if (path == null) return;
      await validateWindowsIso(path, driver: driver);
      if (mounted) {
        setState(() {
          if (driver) {
            _driver = path;
          } else {
            _iso = path;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(bool driver) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = MediaSource(
        kind: ArmMedia.windows,
        url: Uri.parse(driver ? virtioIsoUrl : _url.text.trim()),
        label: driver ? 'VirtIO drivers' : 'Windows 11 x64',
        windowsX64: !driver,
        virtio: driver,
      );
      _session?.removeListener(_changed);
      _session?.dispose();
      final session = MediaDownloadSession(
        source: source,
        directory: widget.directory,
      );
      _session = session;
      session.addListener(_changed);
      await session.start();
      if (!mounted) return;
      setState(() {
        if (session.savedPath != null) {
          if (driver) {
            _driver = session.savedPath;
          } else {
            _iso = session.savedPath;
          }
        }
        _error = session.error;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not download the ISO. Use the official browser download or choose an existing ISO.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = await createWindowsX64Vm(
        directory: widget.directory,
        iso: _iso!,
        driverIso: _driver,
        intelProfile: _intelProfile,
      );
      if (mounted) setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    try {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Could not open the official download page.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the official download page.');
      }
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Windows 11 — x64')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Download the Windows 11 x64 ISO from Microsoft. Select a local ISO, or paste the temporary ISO download link below. Choose x64 media; a file signature alone cannot confirm its architecture.',
        ),
        TextButton(
          onPressed: () => _open(windowsX64Page),
          child: const Text('Open Microsoft download page'),
        ),
        TextField(
          controller: _url,
          enabled: !_busy && _config == null,
          decoration: const InputDecoration(
            labelText: 'Windows 11 x64 ISO download URL',
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            ElevatedButton(
              onPressed: _busy || _config != null
                  ? null
                  : () => _download(false),
              child: const Text('Download ISO'),
            ),
            TextButton(
              onPressed: _busy || _config != null ? null : () => _pick(false),
              child: const Text('Choose existing ISO'),
            ),
          ],
        ),
        SelectableText(_iso ?? 'No Windows ISO selected'),
        const SizedBox(height: 20),
        const Text(
          'VirtIO driver ISO (optional). The Intel Mac profile uses SATA and Intel networking. If the driver server returns an HTML page, use the official browser download and select the complete ISO.',
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _busy || _config != null
                  ? null
                  : () => _download(true),
              child: const Text('Download VirtIO ISO'),
            ),
            TextButton(
              onPressed: _busy || _config != null ? null : () => _pick(true),
              child: const Text('Choose driver ISO'),
            ),
            TextButton(
              onPressed: () => _open(virtioIsoUrl),
              child: const Text('Open driver download'),
            ),
            if (_driver != null)
              TextButton(
                onPressed: _busy || _config != null
                    ? null
                    : () => setState(() => _driver = null),
                child: const Text('Detach drivers'),
              ),
          ],
        ),
        if (_driver != null) SelectableText(_driver!),
        if (isIntelMac)
          CheckboxListTile(
            value: _intelProfile,
            onChanged: _busy || _config != null
                ? null
                : (value) => setState(() => _intelProfile = value!),
            title: const Text('Use Windows x64 on Intel Mac profile'),
            subtitle: const Text(
              'Experimental installation profile: Nehalem/HVF, SATA, Intel network. TPM and Secure Boot are disabled; Windows 11 setup may require a separate requirements workaround.',
            ),
          ),
        const Text(
          'Manual installation. No unattended ISO or answer file is generated. Existing VMs and disks are not overwritten. After creating the VM, return to the manager to start installation.',
        ),
        if (_busy) ...[
          LinearProgressIndicator(
            value: _session != null && !_session!.finished
                ? _session!.progress
                : null,
          ),
          if (_session != null && !_session!.finished) ...[
            Text(
              '${_session!.received} / ${_session!.total ?? "unknown"} bytes',
            ),
            TextButton(
              onPressed: () => unawaited(_session!.cancel()),
              child: const Text('Cancel download'),
            ),
          ],
        ],
        if (_error != null)
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ElevatedButton(
          onPressed: _busy || _iso == null || _config != null ? null : _create,
          child: const Text('Create VM'),
        ),
        if (_config != null) SelectableText('VM created: $_config'),
      ],
    ),
  );
}
