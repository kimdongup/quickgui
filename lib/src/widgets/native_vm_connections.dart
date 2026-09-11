import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import '../globals.dart';
import '../services/connections.dart';
import '../services/native_connections.dart';
import '../services/native_vm.dart';

class NativeVmConnections extends StatefulWidget {
  const NativeVmConnections({
    required this.vm,
    required this.service,
    required this.onChanged,
    super.key,
  });
  final NativeVmRecord vm;
  final NativeVmService service;
  final Future<void> Function() onChanged;
  @override
  State<NativeVmConnections> createState() => _NativeVmConnectionsState();
}

class _NativeVmConnectionsState extends State<NativeVmConnections> {
  bool busy = false;
  Future<void> error(Object error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Connection error')),
        content: SelectableText(nativeVmError(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('OK')),
          ),
        ],
      ),
    );
  }

  Future<void> connect(bool spice) async {
    setState(() => busy = true);
    try {
      final executable = spice
          ? nativeSpiceViewer(gToolchain)
          : findTerminal(gToolchain);
      if (executable == null) {
        throw StateError(
          spice
              ? 'Install spicy to open the SPICE display.'
              : 'No supported terminal found.',
        );
      }
      String username = '';
      if (!spice) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t('Connect with SSH')),
            content: TextField(
              autofocus: true,
              onChanged: (value) => username = value.trim(),
              decoration: InputDecoration(
                labelText: context.t('SSH username'),
                helperText: context.t(
                  'Enter your Windows account name. Enter its password in the terminal.',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t('Cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (username.isNotEmpty) Navigator.pop(context, true);
                },
                child: Text(context.t('Connect')),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted) return;
      }
      final args = spice
          ? await nativeSpiceArguments(widget.vm, widget.service)
          : sshArguments(
              executable,
              await nativeSshPort(widget.vm, widget.service),
              username,
            );
      // The viewer can outlive this widget; don't keep controls busy until it closes.
      unawaited(
        launchConnection(
          executable,
          args,
          directory: p.dirname(widget.vm.path),
          environment: gProcessEnvironment,
        ).catchError((Object e) async {
          await error(e);
        }),
      );
      await widget.onChanged();
    } catch (e) {
      await error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> configure() async {
    final vm = await widget.service.status(widget.vm.path);
    if (!mounted) return;
    if (!vm.canStart) {
      await error(StateError('Shut down Windows before changing connections.'));
      return;
    }
    var port = vm.savedSshPort?.toString() ?? '22220';
    var spice = vm.spiceRequested;
    String? validation;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.t('Windows connections')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: port,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => port = value,
                  decoration: InputDecoration(
                    labelText: context.t('Local SSH port'),
                    errorText: validation,
                    helperText: '127.0.0.1 → Windows:22',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.t('Enable SPICE display')),
                  subtitle: Text(
                    context.t(
                      vm.spiceAvailable
                          ? 'Cocoa display remains available.'
                          : 'ARM SPICE backend is missing. Cocoa will be used.',
                    ),
                  ),
                  value: spice,
                  onChanged: (value) => update(() => spice = value),
                ),
                Text(
                  context.t(
                    'Install and start OpenSSH Server inside Windows to use SSH. Connection settings do not change guest accounts or passwords.',
                  ),
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
              onPressed: () {
                final number = int.tryParse(port);
                if (number == null || number < 1024 || number > 65535) {
                  update(
                    () => validation = context.t(
                      'Use a port from 1024 to 65535.',
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(context.t('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.service.configureConnections(
        vm.path,
        port: int.parse(port),
        spiceEnabled: spice,
      );
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vm.hasSsh) SelectableText('SSH: 127.0.0.1:${vm.sshPort}'),
        if (vm.hasSpice) Text(context.t('SPICE display available')),
        if (vm.connectionWarning != null) Text(vm.connectionWarning!),
        Wrap(
          spacing: 8,
          children: [
            if (vm.canStart)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await configure();
                        } catch (e) {
                          await error(e);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.settings_ethernet),
                label: Text(context.t('Connections')),
              ),
            if (vm.hasSsh)
              TextButton.icon(
                onPressed: busy ? null : () => connect(false),
                icon: const Icon(Icons.terminal),
                label: Text(context.t('Connect with SSH')),
              ),
            if (vm.hasSpice)
              TextButton.icon(
                onPressed: busy ? null : () => connect(true),
                icon: const Icon(Icons.monitor),
                label: Text(context.t('Connect display with SPICE')),
              ),
          ],
        ),
      ],
    );
  }
}
