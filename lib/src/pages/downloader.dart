import 'dart:async';
import 'dart:io';

import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:gettext_i18n/gettext_i18n.dart';

import '../globals.dart';
import '../model/operating_system.dart';
import '../model/option.dart';
import '../model/version.dart';
import '../services/download_session.dart';
import '../widgets/downloader/cancel_dismiss_button.dart';
import '../widgets/downloader/download_progress_bar.dart';

class Downloader extends StatefulWidget {
  const Downloader({
    required this.operatingSystem,
    required this.version,
    this.option,
    this.session,
    this.directory,
    super.key,
  });
  final OperatingSystem operatingSystem;
  final Version version;
  final Option? option;
  final DownloadSession? session;
  final String? directory;
  @override
  State<Downloader> createState() => _DownloaderState();
}

class _DownloaderState extends State<Downloader> with WidgetsBindingObserver {
  late final DownloadSession session;
  NotificationsClient? _notifications;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session =
        widget.session ??
        DownloadSession(
          executable: gQuickgetExecutable ?? 'quickget',
          arguments: [
            widget.operatingSystem.code,
            widget.version.version,
            if (widget.option?.option.isNotEmpty ?? false)
              widget.option!.option,
          ],
          directory: widget.directory ?? workingDirectory,
          environment: Map.of(gProcessEnvironment),
          runner: gRunner,
        );
    session.addListener(_changed);
    unawaited(_start());
  }

  Future<void> _start() async {
    await session.start();
    if (!mounted || Platform.isMacOS) return;
    try {
      _notifications = NotificationsClient();
      await _notifications!.notify(
        _label(),
        appName: 'Quickgui',
        expireTimeoutMs: 10000,
      );
    } catch (_) {
      /* Notification availability cannot change the download result. */
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _label() => switch (session.status) {
    DownloadStatus.succeeded => context.t('Download complete'),
    DownloadStatus.failed => context.t('Download failed'),
    DownloadStatus.cancelled => context.t('Download cancelled'),
    DownloadStatus.cancelling => context.t('Cancelling download'),
    DownloadStatus.starting => context.t('Waiting for download to start'),
    DownloadStatus.running =>
      session.progress == null
          ? context.t('Downloading (no progress available)...')
          : context.t(
              'Downloading... {0}%',
              args: [(session.progress! * 100).toInt()],
            ),
  };

  Future<bool> _confirmExit() async {
    if (session.finished) return true;
    if (_confirming) return false;
    _confirming = true;
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Cancel download?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('OK')),
            ),
          ],
        ),
      );
      if (confirm != true) return false;
      await session.cancel();
      try {
        await session.done.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        return false;
      }
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      return session.finished;
    } finally {
      _confirming = false;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async =>
      await _confirmExit() ? AppExitResponse.exit : AppExitResponse.cancel;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_changed);
    session.dispose();
    unawaited(_notifications?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: session.finished,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (await _confirmExit() && context.mounted) Navigator.of(context).pop();
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          context.t(
            'Downloading {0}',
            args: [
              '${widget.operatingSystem.name} ${widget.version.version}${widget.option?.option.isNotEmpty ?? false ? ' (${widget.option!.option})' : ''}',
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_label()),
                    const SizedBox(height: 8),
                    DownloadProgressBar(
                      downloadFinished: session.finished,
                      data: session.progress,
                    ),
                    if (session.error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(session.error!),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Text(
                        context.t(
                          'Target folder : {0}',
                          args: [session.directory],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          CancelDismissButton(
            downloadFinished: session.finished,
            onCancel: () => unawaited(session.cancel()),
          ),
        ],
      ),
    ),
  );
}
