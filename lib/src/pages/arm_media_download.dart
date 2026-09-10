import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../model/operating_system.dart';
import '../services/arm_media.dart';
import '../services/download_session.dart' show DownloadStatus;
import 'native_vm_create.dart';
import '../services/native_vm.dart';
import 'installation_media.dart';

class ArmMediaDownload extends StatefulWidget {
  const ArmMediaDownload({
    required this.kind,
    required this.directory,
    this.restoreImage,
    super.key,
  });
  final ArmMedia kind;
  final String directory;
  final Future<MediaSource> Function()? restoreImage;
  @override
  State<ArmMediaDownload> createState() => _ArmMediaDownloadState();
}

class _ArmMediaDownloadState extends State<ArmMediaDownload>
    with WidgetsBindingObserver {
  final _url = TextEditingController();
  MediaSource? _source;
  MediaDownloadSession? _session;
  bool _loading = false, _confirming = false;
  String? _error;
  bool get _active => _session != null && !_session!.finished;
  bool get _windows => widget.kind == ArmMedia.windows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_windows) unawaited(_loadImage());
  }

  Future<void> _loadImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = await (widget.restoreImage ?? latestMacRestoreImage)();
      if (mounted) setState(() => _source = source);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not find a compatible image. Use an Apple Silicon Mac with macOS 12 or later and check the connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_active) return;
    try {
      final source = _windows
          ? MediaSource(
              kind: ArmMedia.windows,
              url: Uri.parse(_url.text.trim()),
              label: 'Windows 11 — ARM64',
            )
          : _source!;
      _session?.removeListener(_changed);
      _session?.dispose();
      final session = MediaDownloadSession(
        source: source,
        directory: widget.directory,
      );
      setState(() {
        _error = null;
        _session = session;
      });
      session.addListener(_changed);
      await session.start();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the download.');
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Open failed');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the link or folder.');
      }
    }
  }

  Future<void> _manageFiles() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstallationMedia(directory: widget.directory),
      ),
    );
    final saved = _session?.savedPath;
    if (saved != null && !await File(saved).exists() && mounted) {
      _session?.removeListener(_changed);
      _session?.dispose();
      setState(() => _session = null);
    }
  }

  Future<bool> _canExit() async {
    if (!_active) return true;
    if (_confirming) return false;
    _confirming = true;
    try {
      final cancel = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Cancel download?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Keep downloading')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Cancel download')),
            ),
          ],
        ),
      );
      if (cancel != true) return false;
      await _session?.cancel();
      return true;
    } finally {
      _confirming = false;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async =>
      await _canExit() ? AppExitResponse.exit : AppExitResponse.cancel;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_changed);
    _session?.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final saved = session?.savedPath;
    return PopScope(
      canPop: !_active,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _canExit() && context.mounted) {
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _windows ? 'Windows 11 — ARM64' : 'macOS — Apple Silicon ARM64',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('Download installation image'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.t(
                  _windows
                      ? 'Download a Windows ARM64 ISO, then create a VM. You can also use an ISO already on this Mac.'
                      : 'Download an IPSW, then create and install an Apple Silicon VM. You can also use an IPSW already on this Mac.',
                ),
              ),
              const SizedBox(height: 16),
              if (_windows) ...[
                Text(
                  context.t(
                    'Open Microsoft’s ARM64 download page, choose a language, then copy the ISO download link here. Links expire after 24 hours.',
                  ),
                ),
                TextButton.icon(
                  onPressed: _active
                      ? null
                      : () => _open(Uri.parse(windowsArmPage)),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.t('Open Microsoft ARM64 downloads')),
                ),
                TextField(
                  controller: _url,
                  enabled: !_active,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.t('ARM64 ISO download link'),
                    hintText: 'https://software.download.prss.microsoft.com/…Arm64.iso?…',
                  ),
                ),
              ] else ...[
                if (_loading) const LinearProgressIndicator(),
                if (_source != null) Text(_source!.label),
                if (!_loading && _source == null)
                  TextButton(
                    onPressed: _loadImage,
                    child: Text(context.t('Retry')),
                  ),
                Text(
                  context.t(
                    'Apple provides the latest restore image compatible with this Mac.',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (Platform.isMacOS && !_active)
                TextButton.icon(
                  onPressed: _manageFiles,
                  icon: const Icon(Icons.folder_delete_outlined),
                  label: Text(context.t('Installation files')),
                ),
              if (!_active)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NativeVmCreate(
                        directory: widget.directory,
                        imagePath: saved,
                        service: NativeVmService(
                          kind: _windows
                              ? NativeVmKind.windows
                              : NativeVmKind.macos,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.computer),
                  label: Text(
                    context.t(
                      _windows
                          ? (saved == null
                                ? 'Use an existing ARM64 ISO'
                                : 'Create Windows ARM64 VM')
                          : (saved == null
                                ? 'Use an existing IPSW'
                                : 'Create Apple Silicon VM'),
                    ),
                  ),
                ),
              SelectableText(
                context.t(
                  'Target folder : {0}',
                  args: [p.join(widget.directory, 'Install Media')],
                ),
              ),
              if (_error ?? session?.error case final String error) ...[
                const SizedBox(height: 12),
                SelectableText(context.t(error)),
              ],
              if (_active) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: session!.progress),
                Text(
                  '${(session.received / (1024 * 1024)).toStringAsFixed(1)} MiB'
                  '${session.total == null ? '' : ' / ${(session.total! / (1024 * 1024)).toStringAsFixed(1)} MiB'}',
                ),
              ],
              if (session?.status == DownloadStatus.cancelled)
                Text(context.t('Download cancelled')),
              if (saved != null) ...[
                const SizedBox(height: 16),
                Text(
                  context.t(
                    'Installation image saved. VM setup is still required.',
                  ),
                ),
                SelectableText(saved),
                TextButton.icon(
                  onPressed: () => _open(Uri.directory(p.dirname(saved))),
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.t('Open download folder')),
                ),
              ],
              const SizedBox(height: 20),
              if (saved == null)
                FilledButton(
                  onPressed:
                      _active || _loading || (!_windows && _source == null)
                      ? null
                      : _start,
                  child: Text(
                    context.t(_windows ? 'Download ISO' : 'Download IPSW'),
                  ),
                ),
              if (_active)
                TextButton(
                  onPressed: () => session!.cancel(),
                  child: Text(context.t('Cancel download')),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t('Close')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
