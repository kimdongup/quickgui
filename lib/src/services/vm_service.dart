import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:version/version.dart';

import 'command_runner.dart';

enum VmState { stopped, running, unknown }

enum VmAction { start, stop, deleteDisk, deleteVm, edit, confirmInstallation }

class VmRecord {
  VmRecord({
    required this.configPath,
    required this.content,
    required this.state,
    this.stateDirectory,
    this.pid,
    this.sshPort,
    this.spicePort,
    this.spiceSocketPath,
    this.error,
    this.installationPending = false,
  });
  final String configPath, content;
  final VmState state;
  final String? stateDirectory, error, spiceSocketPath;
  final int? pid, sshPort, spicePort;
  final bool installationPending;
  String get name => p.basenameWithoutExtension(configPath);
  String get directory => p.dirname(configPath);
  bool get hasSpice => spiceSocketPath != null || spicePort != null;
}

/// Only literal assignments are interpreted. Bash expressions are never sourced.
String? configLiteral(String content, String key) {
  final matches = RegExp(
    '^\\s*${RegExp.escape(key)}\\s*=\\s*(.*?)\\s*\$',
    multiLine: true,
  ).allMatches(content);
  if (matches.length != 1) return null;
  var value = matches.single[1]!;
  if (value.startsWith("'")) {
    final match = RegExp(r"^'([^']*)'\s*(?:#.*)?$").firstMatch(value);
    return match?[1];
  }
  if (value.startsWith('"')) {
    final match = RegExp(r'^"([^"$`\\]*)"\s*(?:#.*)?$').firstMatch(value);
    return match?[1];
  }
  value = value.split(RegExp(r'\s+#')).first.trim();
  return RegExp(r'^[a-zA-Z0-9_./:+-]+$').hasMatch(value) ? value : null;
}

int? parsePort(String text) {
  final value = int.tryParse(text);
  return value != null && value > 0 && value <= 65535 ? value : null;
}

class VmRepository {
  const VmRepository({this.runner = const CommandRunner()});
  final CommandRunner runner;

  Future<List<VmRecord>> list(String directory) async {
    final records = <VmRecord>[];
    await for (final entity in Directory(directory).list(followLinks: true)) {
      if (!entity.path.endsWith('.conf')) continue;
      try {
        if (await FileSystemEntity.type(entity.path) !=
            FileSystemEntityType.file) {
          continue;
        }
        final record = await inspect(p.normalize(p.absolute(entity.path)));
        if (record != null) records.add(record);
      } catch (e) {
        records.add(
          VmRecord(
            configPath: entity.path,
            content: '',
            state: VmState.unknown,
            error: '$e',
          ),
        );
      }
    }
    records.sort((a, b) => a.name.compareTo(b.name));
    return records;
  }

  Future<VmRecord?> inspect(String configPath) async {
    final content = await File(configPath).readAsString();
    if (!RegExp(r'^\s*guest_os\s*=', multiLine: true).hasMatch(content)) {
      return null;
    }
    final disk = configLiteral(content, 'disk_img');
    if (disk == null || disk.isEmpty) {
      return VmRecord(
        configPath: configPath,
        content: content,
        state: VmState.unknown,
        error: 'Cannot determine disk_img from a literal assignment.',
      );
    }
    final stateDir = p.dirname(
      p.normalize(
        p.isAbsolute(disk) ? disk : p.join(p.dirname(configPath), disk),
      ),
    );
    final name = p.basenameWithoutExtension(configPath);
    var state = VmState.stopped;
    int? pid, ssh, spice;
    String? error, spiceSocket;
    final pidFile = File(p.join(stateDir, '$name.pid'));
    if (await pidFile.exists()) {
      pid = int.tryParse((await pidFile.readAsString()).trim());
      if (pid == null || pid <= 1) {
        state = VmState.unknown;
        error = 'Invalid VM PID file';
      } else {
        try {
          final result = await runner.run(
            '/bin/ps',
            ['-ww', '-p', '$pid', '-o', 'args='],
            directory: p.dirname(configPath),
            environment: Platform.environment,
          );
          if (result.exitCode == 0) {
            // Verify both QEMU and this VM; an unrelated recycled PID is unknown.
            final pidPaths = [
              p.join(stateDir, '$name.pid'),
              p.join(p.dirname(disk), '$name.pid'),
            ];
            if (RegExp(r'^\S*qemu-system-\S+\s').hasMatch(result.stdout) &&
                pidPaths.any(
                  (path) => RegExp(
                    '(?:^|\\s)-pidfile ${RegExp.escape(path)}(?:\\s|\$)',
                  ).hasMatch(result.stdout),
                )) {
              state = VmState.running;
            } else {
              state = VmState.unknown;
              error = 'PID belongs to an unrecognized process';
            }
          } else if (result.exitCode != 1) {
            state = VmState.unknown;
            error = result.message;
          }
        } catch (e) {
          state = VmState.unknown;
          error = '$e';
        }
      }
    }
    final ports = File(p.join(stateDir, '$name.ports'));
    if (state == VmState.running && await ports.exists()) {
      for (final line in await ports.readAsLines()) {
        // Unix socket paths can themselves contain commas.
        final separator = line.indexOf(',');
        if (separator < 0) continue;
        final kind = line.substring(0, separator);
        final value = line.substring(separator + 1);
        if (kind == 'ssh') ssh = parsePort(value);
        if (kind == 'spice') spice = parsePort(value);
        if (kind == 'unix' && value.isNotEmpty && !value.contains('\u0000')) {
          final path = p.normalize(
            p.isAbsolute(value) ? value : p.join(p.dirname(configPath), value),
          );
          if (await FileSystemEntity.type(path) ==
              FileSystemEntityType.unixDomainSock) {
            spiceSocket = path;
          }
        }
      }
    }
    return VmRecord(
      configPath: configPath,
      content: content,
      stateDirectory: stateDir,
      state: state,
      pid: pid,
      sshPort: ssh,
      spicePort: spice,
      spiceSocketPath: spiceSocket,
      error: error,
      installationPending:
          await FileSystemEntity.type(
            p.join(stateDir, 'installation-in-progress'),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound,
    );
  }
}

// Resolve existing ancestors too: a disk may be absent after Delete disk while
// its directory is still reached through a symbolic link.
Future<String> _resolvedStoragePath(String path) async {
  final absolute = p.normalize(p.absolute(path));
  if (await FileSystemEntity.type(absolute) != FileSystemEntityType.notFound) {
    return File(absolute).resolveSymbolicLinks();
  }
  final parent = p.dirname(absolute);
  if (parent == absolute) return absolute;
  return p.join(await _resolvedStoragePath(parent), p.basename(absolute));
}

class VmOperations extends ChangeNotifier {
  VmOperations({
    this.repository = const VmRepository(),
    this.runner = const CommandRunner(),
    this.startTimeout = const Duration(seconds: 12),
    this.isMacOS = false,
  });
  final VmRepository repository;
  final CommandRunner runner;
  final Duration startTimeout;
  final bool isMacOS;
  final Map<String, VmAction> _busy = {};
  VmAction? actionFor(String config) => _busy[config];

  Future<void> saveConfig(VmRecord selected, String content) async {
    final file = File(selected.configPath);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Open the original config file to edit a symbolic link');
    }
    final key = await file.resolveSymbolicLinks();
    if (_busy.containsKey(key) || _busy.containsKey(file.path)) {
      throw StateError('VM already has an operation in progress');
    }
    _busy[key] = VmAction.edit;
    _busy[file.path] = VmAction.edit;
    notifyListeners();
    Directory? temporary;
    try {
      Future<void> check() async {
        final current = await repository.inspect(file.path);
        if (current?.state != VmState.stopped ||
            current?.content != selected.content ||
            await file.resolveSymbolicLinks() != key ||
            await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw StateError('VM or config changed; close and reopen the editor');
        }
      }

      await check();
      final stat = await file.stat();
      temporary = await Directory(selected.directory)
          .createTemp('.quickgui-edit-');
      final replacement = await File(p.join(temporary.path, 'config'))
          .writeAsString(content, flush: true);
      final mode = (stat.mode & 0x1ff).toRadixString(8);
      final chmod = await Process.run('/bin/chmod', [mode, replacement.path]);
      if (chmod.exitCode != 0) {
        throw FileSystemException(
          'Cannot preserve config permissions',
          file.path,
        );
      }
      await check();
      // Same-filesystem rename preserves the original if preparing the file fails.
      await replacement.rename(file.path);
    } finally {
      try {
        if (temporary != null) await temporary.delete(recursive: true);
      } finally {
        _busy.remove(key);
        _busy.remove(file.path);
        notifyListeners();
      }
    }
  }

  Future<void> perform(
    VmRecord selected,
    VmAction action, {
    required String executable,
    required Map<String, String> environment,
    List<String> startArguments = const [],
  }) async {
    if (action == VmAction.edit) {
      throw ArgumentError('Use saveConfig for editing');
    }
    // Resolve aliases so two symlink names cannot bypass a per-VM lock.
    final key = await File(selected.configPath).resolveSymbolicLinks();
    if (_busy.containsKey(key) || _busy.containsKey(selected.configPath)) {
      throw StateError('VM already has an operation in progress');
    }
    _busy[key] = action;
    _busy[selected.configPath] = action;
    notifyListeners();
    try {
      final current = await repository.inspect(selected.configPath);
      if (current == null || current.content != selected.content) {
        throw StateError('VM configuration changed; refresh and try again');
      }
      final requiredState = action == VmAction.stop
          ? VmState.running
          : VmState.stopped;
      if (current.state != requiredState) {
        throw StateError(
          current.error ?? 'VM state changed; refresh and try again',
        );
      }
      if (action == VmAction.start && current.installationPending) {
        throw StateError(
          'Installation is still marked in progress. Complete guest setup and '
          'confirm installation in Manager before using Run. To resume setup, '
          'use the installer workflow that created this VM.',
        );
      }
      if (action == VmAction.confirmInstallation) {
        await _confirmInstallation(current);
        return;
      }
      if (action == VmAction.start && isMacOS) {
        final help = await runner.run(
          executable,
          ['--help'],
          directory: current.directory,
          environment: environment,
        );
        help.requireSuccess();
        startArguments = [
          ...startArguments,
          ...macStartArguments(
            current.content,
            help.stdout,
            explicitArguments: startArguments,
          ),
        ];
      }
      if (action == VmAction.stop) {
        final versionResult = await runner.run(
          executable,
          ['--version'],
          directory: current.directory,
          environment: environment,
        );
        versionResult.requireSuccess();
        final version = RegExp(r'\d+\.\d+\.\d+')
            .firstMatch(versionResult.stdout)
            ?.group(0);
        if (version == null || Version.parse(version) < Version(4, 9, 6)) {
          throw StateError('Stopping VMs requires Quickemu 4.9.6 or newer');
        }
      }
      if (action == VmAction.deleteVm || action == VmAction.deleteDisk) {
        final wholeVm = action == VmAction.deleteVm;
        final disk = configLiteral(current.content, 'disk_img')!;
        final diskPath = p.isAbsolute(disk)
            ? disk
            : p.join(current.directory, disk);
        final target = await _resolvedStoragePath(
          wholeVm ? current.stateDirectory! : diskPath,
        );
        if (wholeVm) {
          final workspace = await Directory(current.directory)
              .resolveSymbolicLinks();
          if (!p.isWithin(workspace, target)) {
            throw StateError(
              'Whole-VM deletion requires a dedicated directory inside the workspace',
            );
          }
        }
        final otherVms = await repository.list(current.directory);
        for (final vm in otherVms) {
          if (vm.configPath == current.configPath) continue;
          final otherDisk = configLiteral(vm.content, 'disk_img');
          if (otherDisk == null || vm.stateDirectory == null) continue;
          final otherPath = await _resolvedStoragePath(
            p.isAbsolute(otherDisk)
                ? otherDisk
                : p.join(vm.directory, otherDisk),
          );
          final otherDirectory = await _resolvedStoragePath(vm.stateDirectory!);
          if (target == otherPath ||
              (wholeVm &&
                  (target == otherDirectory ||
                      p.isWithin(target, otherDirectory) ||
                      p.isWithin(target, otherPath)))) {
            throw StateError('Another VM uses this disk or directory');
          }
        }
      }
      final arguments = [
        '--vm',
        current.configPath,
        ...switch (action) {
          VmAction.start => startArguments,
          VmAction.stop => ['--kill'],
          VmAction.deleteDisk => ['--delete-disk'],
          VmAction.deleteVm => ['--delete-vm'],
          VmAction.edit => throw StateError('Not a backend action'),
          VmAction.confirmInstallation => throw StateError(
            'Not a backend action',
          ),
        },
      ];
      // Revalidate after all preparatory awaits, especially before destructive commands.
      final latest = await repository.inspect(current.configPath);
      if (latest?.state != requiredState ||
          latest?.content != current.content ||
          (action == VmAction.start && latest!.installationPending)) {
        throw StateError('VM changed while preparing the command');
      }
      final result = await runner.run(
        executable,
        arguments,
        directory: current.directory,
        // The external Windows installer uses this flag to attach unattended
        // repartitioning media. Ordinary Run must never inherit installer mode.
        environment: Map.of(environment)..remove('WINDOWS11_INSTALL'),
        timeout: const Duration(minutes: 2),
      );
      result.requireSuccess();
      if (action == VmAction.deleteVm &&
          await File(current.configPath).exists()) {
        throw StateError('Quickemu did not remove the VM configuration');
      }
      if (action == VmAction.deleteDisk) {
        final disk = configLiteral(current.content, 'disk_img')!;
        final diskPath = p.isAbsolute(disk)
            ? disk
            : p.join(current.directory, disk);
        if (await File(diskPath).exists()) {
          throw StateError('Quickemu did not remove the disk image');
        }
      }
      if (action == VmAction.start || action == VmAction.stop) {
        final deadline = DateTime.now().add(startTimeout);
        while (DateTime.now().isBefore(deadline)) {
          final observed = await repository.inspect(current.configPath);
          if (observed?.state ==
              (action == VmAction.start ? VmState.running : VmState.stopped)) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        final logFile = File(
          p.join(current.stateDirectory!, '${current.name}.log'),
        );
        var detail = '';
        if (await logFile.exists()) {
          final length = await logFile.length();
          detail = await logFile
              .openRead(length > 65536 ? length - 65536 : 0)
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
        }
        throw StateError('VM did not reach the expected state.\n$detail');
      }
    } finally {
      _busy.remove(key);
      _busy.remove(selected.configPath);
      notifyListeners();
    }
  }

  Future<void> _confirmInstallation(VmRecord current) async {
    final marker = File(
      p.join(current.stateDirectory!, 'installation-in-progress'),
    );
    final workspace = await Directory(current.directory).resolveSymbolicLinks();
    final stateDirectory = await Directory(current.stateDirectory!)
        .resolveSymbolicLinks();
    if (!current.installationPending ||
        !p.isWithin(workspace, stateDirectory) ||
        await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError(
        'Installation confirmation requires a regular marker in this VM directory',
      );
    }
    final others = await repository.list(current.directory);
    for (final vm in others) {
      if (vm.configPath == current.configPath || vm.stateDirectory == null) {
        continue;
      }
      if (await Directory(vm.stateDirectory!).exists() &&
          await Directory(vm.stateDirectory!).resolveSymbolicLinks() ==
              stateDirectory) {
        throw StateError('Another VM uses this installation directory');
      }
    }
    final latest = await repository.inspect(current.configPath);
    if (latest?.state != VmState.stopped ||
        latest?.content != current.content ||
        latest?.stateDirectory != current.stateDirectory ||
        await Directory(current.stateDirectory!).resolveSymbolicLinks() !=
            stateDirectory ||
        await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('VM changed while confirming installation');
    }
    // Keep the original marker as evidence. No disk, config or installer is edited.
    final archive = await Directory(stateDirectory)
        .createTemp('.quickgui-installation-completed-');
    try {
      await marker.rename(p.join(archive.path, 'installation-in-progress'));
    } catch (_) {
      await archive.delete();
      rethrow;
    }
  }
}

List<String> macStartArguments(
  String content,
  String help, {
  List<String> explicitArguments = const [],
}) => [
  if (!explicitArguments.contains('--display'))
    if (!RegExp(r'^\s*display\s*=', multiLine: true).hasMatch(content) &&
        help.contains('cocoa')) ...[
      '--display',
      'cocoa',
    ],
  if (!explicitArguments.contains('--sound-duplex') &&
      !RegExp(r'^\s*sound_duplex\s*=', multiLine: true).hasMatch(content) &&
      help.contains('hda-output')) ...[
    '--sound-duplex',
    'hda-output',
  ],
];

final vmOperations = VmOperations(isMacOS: Platform.isMacOS);
