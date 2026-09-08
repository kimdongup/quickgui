import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../globals.dart';
import '../model/osicons.dart';
import '../services/connections.dart';
import '../services/vm_service.dart';
import '../widgets/workspace_picker.dart';

class Manager extends StatefulWidget {
  const Manager({this.operations, super.key});
  final VmOperations? operations;
  @override
  State<Manager> createState() => _ManagerState();
}

class _ManagerState extends State<Manager> {
  late final VmOperations operations;
  List<VmRecord> _vms = [];
  final Set<String> _ssh = {};
  String? _terminal, _spicy, _error;
  Timer? _timer;
  bool _refreshing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    operations = widget.operations ?? vmOperations;
    operations.addListener(_changed);
    gWorkspace?.addListener(_workspaceChanged);
    try {
      _terminal = findTerminal(gToolchain);
    } catch (_) {
      _terminal = null;
    }
    _spicy = findExecutable('spicy');
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refresh()),
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _workspaceChanged() {
    _generation++;
    _vms = [];
    _ssh.clear();
    _changed();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final directory = workingDirectory, generation = _generation;
    try {
      final vms = await operations.repository.list(directory);
      if (!mounted || generation != _generation) return;
      setState(() {
        _vms = vms;
        _error = null;
      });
      final detected = <String>{};
      // Keep socket work out of build; each connection has a bounded lifetime.
      for (var i = 0; i < vms.length; i += 8) {
        if (!mounted || generation != _generation) return;
        final batch = vms.skip(i).take(8);
        await Future.wait(
          batch.map((vm) async {
            if (_terminal != null &&
                vm.state == VmState.running &&
                vm.sshPort != null &&
                await detectSsh(vm.sshPort!)) {
              detected.add(vm.configPath);
            }
          }),
        );
      }
      if (mounted && generation == _generation) {
        setState(() {
          _ssh
            ..clear()
            ..addAll(detected);
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$e';
          _vms = [];
          _ssh.clear();
        });
      }
    } finally {
      _refreshing = false;
      if (mounted && generation != _generation) unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    operations.removeListener(_changed);
    gWorkspace?.removeListener(_workspaceChanged);
    super.dispose();
  }

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Error')),
        content: SingleChildScrollView(child: SelectableText('$error')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('OK')),
          ),
        ],
      ),
    );
  }

  Future<void> _perform(VmRecord vm, VmAction action) async {
    try {
      final executable = gQuickemuExecutable;
      if (executable == null) throw StateError('quickemu was not found');
      await operations.perform(
        vm,
        action,
        executable: executable,
        environment: Map.of(gProcessEnvironment),
        startArguments:
            Platform.isLinux &&
                _spicy != null &&
                !RegExp(
                  r'^\s*display\s*=',
                  multiLine: true,
                ).hasMatch(vm.content)
            ? ['--display', 'spice']
            : [],
      );
    } catch (e) {
      await _showError(e);
    } finally {
      if (mounted) await _refresh();
    }
  }

  Future<void> _stop(VmRecord vm) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Stop The Virtual Machine?')),
        content: Text(
          context.t(
            'You are about to terminate the virtual machine {0}',
            args: [vm.name],
          ),
        ),
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
    if (result == true && mounted) await _perform(vm, VmAction.stop);
  }

  Future<void> _delete(VmRecord vm) async {
    final result = await showDialog<VmAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Delete {0}', args: [vm.name])),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(
                  'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?',
                  args: [vm.name],
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(vm.stateDirectory ?? vm.configPath),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, VmAction.deleteDisk),
            child: Text(context.t('Delete disk image')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, VmAction.deleteVm),
            child: Text(context.t('Delete whole VM')),
          ),
        ],
      ),
    );
    if (result != null && mounted) await _perform(vm, result);
  }

  Future<void> _connectSsh(VmRecord vm) async {
    String username = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Launch SSH connection to {0}', args: [vm.name])),
        content: TextField(
          autofocus: true,
          onChanged: (text) => username = text,
          decoration: InputDecoration(hintText: context.t('SSH username')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
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
    if (result != true || !mounted) return;
    try {
      await launchConnection(
        _terminal!,
        sshArguments(_terminal!, vm.sshPort!, username),
        directory: vm.directory,
        environment: gProcessEnvironment,
      );
    } catch (e) {
      await _showError(e);
    }
  }

  Widget _icon(VmRecord vm) {
    var stem = vm.name;
    while (stem.contains('-')) {
      stem = stem.substring(0, stem.lastIndexOf('-'));
      if (osIcons.containsKey(stem)) {
        return SvgPicture.asset(osIcons[stem]!, width: 32, height: 32);
      }
    }
    return const Icon(Icons.computer, size: 32);
  }

  List<Widget> _row(VmRecord vm) {
    final active = vm.state == VmState.running;
    final busy = operations.actionFor(vm.configPath) != null;
    final stopped = vm.state == VmState.stopped;
    final color = Theme.of(context).colorScheme.primary;
    final info = [
      if (vm.spicePort != null) '${context.t('SPICE port')}: ${vm.spicePort}',
      if (vm.sshPort != null) '${context.t('SSH port')}: ${vm.sshPort}',
    ].join(' ');
    return [
      ListTile(
        leading: _icon(vm),
        title: Text(vm.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: vm.error == null
            ? null
            : Tooltip(
                message: vm.error!,
                child: Text(
                  vm.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.t('Run'),
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      active ? Icons.play_arrow : Icons.play_arrow_outlined,
                      color: active ? Colors.green : color,
                    ),
              onPressed: stopped && !busy
                  ? () => _perform(vm, VmAction.start)
                  : null,
            ),
            IconButton(
              tooltip: context.t('Stop'),
              icon: Icon(
                active ? Icons.stop : Icons.stop_outlined,
                color: active ? Colors.red : null,
              ),
              onPressed: active && !busy ? () => _stop(vm) : null,
            ),
            IconButton(
              tooltip: context.t('Delete'),
              icon: const Icon(Icons.delete),
              onPressed: stopped && !busy ? () => _delete(vm) : null,
            ),
          ],
        ),
      ),
      if (active && info.isNotEmpty)
        ListTile(
          title: Text(info, style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.t(
                  _spicy == null
                      ? 'SPICE client not found'
                      : 'Connect display with SPICE',
                ),
                icon: const Icon(Icons.monitor),
                onPressed: _spicy != null && vm.spicePort != null
                    ? () async {
                        try {
                          await launchConnection(
                            _spicy!,
                            ['-p', '${vm.spicePort}'],
                            directory: vm.directory,
                            environment: gProcessEnvironment,
                          );
                        } catch (e) {
                          await _showError(e);
                        }
                      }
                    : null,
              ),
              IconButton(
                tooltip: context.t(
                  _ssh.contains(vm.configPath)
                      ? 'Connect with SSH'
                      : 'SSH server not detected on guest',
                ),
                icon: SvgPicture.asset(
                  'assets/images/console.svg',
                  colorFilter: ColorFilter.mode(
                    _ssh.contains(vm.configPath) ? color : Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                onPressed: _ssh.contains(vm.configPath)
                    ? () => _connectSsh(vm)
                    : null,
              ),
            ],
          ),
        ),
      const Divider(),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('Manager'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const WorkspacePicker(),
        const Divider(thickness: 2),
        if (_error != null) ...[
          SelectableText(_error!),
          TextButton(onPressed: _refresh, child: Text(context.t('Retry'))),
        ],
        for (final vm in _vms) ..._row(vm),
      ],
    ),
  );
}
