import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import '../services/native_vm.dart';
import '../services/native_storage.dart';
import 'storage_delete_dialog.dart';
import 'native_vm_connections.dart';

class NativeVmControls extends StatefulWidget {
  const NativeVmControls({
    required this.vm,
    required this.service,
    required this.onChanged,
    this.allowDelete = false,
    this.storage = const NativeStorageService(),
    super.key,
  });
  final NativeVmRecord vm;
  final NativeVmService service;
  final Future<void> Function() onChanged;
  final bool allowDelete;
  final NativeStorageService storage;
  @override
  State<NativeVmControls> createState() => _NativeVmControlsState();
}

class _NativeVmControlsState extends State<NativeVmControls> {
  bool _busy = false;
  Future<void> _action(
    Future<void> Function() action, {
    String? confirmation,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (confirmation != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t('Confirm')),
            content: Text(context.t(confirmation)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.t('Continue')),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await action();
      await widget.onChanged();
    } catch (error) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t('Error')),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm, service = widget.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t(vm.label)),
        if (vm.state == 'installing' || vm.state == 'cancelling') ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: vm.progress),
          if (vm.progress != null)
            Text('${(vm.progress! * 100).toStringAsFixed(1)}%'),
        ],
        if (vm.error != null) SelectableText(vm.error!),
        if (service.windows)
          NativeVmConnections(
            vm: vm,
            service: service,
            onChanged: widget.onChanged,
          ),
        Wrap(
          spacing: 8,
          children: [
            if (service.windows)
              TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(context.t('Windows network setup')),
                    content: SelectableText(
                      context.t(
                        'At the Windows network screen, choose Install driver. Browse to the QGNET CD, select the NetKVM folder, and install the ARM64 network driver. Windows will use Ethernet through this Mac.\n\nIf QGNET is missing, prepare the network driver CD on this Mac and restart the VM. On an installed Windows desktop, use Device Manager to update the Ethernet controller driver from the same folder.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.t('OK')),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.network_check),
                label: Text(context.t('Network setup')),
              ),
            if (vm.canStart)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _action(() => service.start(vm.path)),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  context.t(
                    vm.installationPending ? 'Resume installation' : 'Run',
                  ),
                ),
              ),
            if (vm.canStart && vm.installationPending)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        () => service.completeInstallation(vm.path),
                        confirmation: 'Confirm only after reaching the Windows desktop and shutting down the guest. Future runs will boot from the disk without the installation ISO.',
                      ),
                child: Text(context.t('Installation completed')),
              ),
            if (vm.canShow)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _action(() => service.show(vm.path)),
                icon: const Icon(Icons.monitor),
                label: Text(context.t('Open VM display')),
              ),
            if (vm.canStop)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(() => service.stop(vm.path)),
                child: Text(context.t('Shut down')),
              ),
            if (vm.canForceStop)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        () => service.stop(vm.path, force: true),
                        confirmation: 'Force stop this VM? Unsaved work in the guest may be lost.',
                      ),
                child: Text(context.t('Force stop')),
              ),
            if (vm.canCancel)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        () => service.cancelInstall(vm.path),
                        confirmation: 'Cancel macOS installation? The unfinished VM will be kept. Create a new VM to try again.',
                      ),
                child: Text(context.t('Cancel installation')),
              ),
            if (widget.allowDelete && vm.canDelete)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        final directory = p.dirname(vm.path);
                        final preview = await widget.storage.preview(
                          path: vm.path,
                          directory: directory,
                          isVM: true,
                        );
                        if (!context.mounted) return;
                        if (!await confirmStorageDeletion(context, preview)) {
                          return;
                        }
                        await widget.storage.delete(
                          preview,
                          directory: directory,
                        );
                      }),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.t('Delete VM')),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
