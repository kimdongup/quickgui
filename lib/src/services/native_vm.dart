import 'package:flutter/services.dart';

enum NativeVmKind { macos, windows }

class NativeInstallationImage {
  NativeInstallationImage(Map<Object?, Object?> data)
    : version = data['version'] as String,
      build = data['build'] as String,
      minimumCPU = data['minimumCPU'] as int,
      maximumCPU = data['maximumCPU'] as int,
      minimumMemoryGiB = data['minimumMemoryGiB'] as int,
      maximumMemoryGiB = data['maximumMemoryGiB'] as int;
  final String version, build;
  final int minimumCPU, maximumCPU, minimumMemoryGiB, maximumMemoryGiB;
}

class NativeVmRecord {
  NativeVmRecord(Map<Object?, Object?> data)
    : path = data['path'] as String,
      name = data['name'] as String,
      state = data['state'] as String,
      error = data['error'] as String?,
      version = data['version'] as String? ?? '',
      installationPending = data['installationPending'] as bool? ?? false,
      progress = (data['progress'] as num?)?.toDouble().clamp(0, 1);
  final String path, name, state, version;
  final String? error;
  final double? progress;
  final bool installationPending;
  bool get canStart => state == 'stopped';
  bool get canShow => state == 'running' || state == 'stopping';
  bool get canCancel => state == 'installing';
  bool get canStop => state == 'running';
  bool get canForceStop => canShow || state == 'error';
  String get label => switch (state) {
    'installing' => 'Installing macOS',
    'cancelling' => 'Cancelling installation',
    'stopped' =>
      installationPending ? 'Windows installation pending' : 'Ready to run',
    'starting' => 'Starting',
    'running' => 'Running',
    'stopping' => 'Waiting for guest shutdown',
    'cancelled' => 'Installation cancelled; create a new VM to try again.',
    'failed' => 'Installation failed; create a new VM to try again.',
    'interrupted' => 'Installation interrupted; create a new VM to try again.',
    'busy' => 'In use by another Quickgui process',
    _ => 'VM unavailable',
  };
}

class NativeVmService {
  const NativeVmService({this.kind = NativeVmKind.macos, this.overrideChannel});
  final NativeVmKind kind;
  final MethodChannel? overrideChannel;
  bool get windows => kind == NativeVmKind.windows;
  String get createLabel =>
      windows ? 'Create Windows ARM64 VM' : 'Create Apple Silicon VM';
  String get title => windows ? 'Windows — ARM64' : 'macOS — Apple Silicon';
  MethodChannel get channel =>
      overrideChannel ??
      MethodChannel(windows ? 'quickgui/windows-arm-vm' : 'quickgui/apple-vm');

  Future<bool> supported() async {
    try {
      return await channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<NativeInstallationImage> inspectImage(String path) async =>
      NativeInstallationImage(
        (await channel.invokeMapMethod<Object?, Object?>('inspectImage', {
          'path': path,
        }))!,
      );

  Future<NativeVmRecord> create({
    required String directory,
    required String name,
    required String imagePath,
    required int cpus,
    required int memoryGiB,
    required int diskGiB,
  }) async => NativeVmRecord(
    (await channel.invokeMapMethod<Object?, Object?>('create', {
      'directory': directory,
      'name': name,
      'image': imagePath,
      'cpus': cpus,
      'memoryGiB': memoryGiB,
      'diskGiB': diskGiB,
    }))!,
  );

  Future<List<NativeVmRecord>> list(String directory) async => [
    for (final row in (await channel.invokeListMethod<Object?>('list', {
      'directory': directory,
    }))!)
      NativeVmRecord(row as Map<Object?, Object?>),
  ];
  Future<NativeVmRecord> status(String path) async => NativeVmRecord(
    (await channel.invokeMapMethod<Object?, Object?>('status', {
      'path': path,
    }))!,
  );
  Future<void> start(String path) =>
      channel.invokeMethod<void>('start', {'path': path});
  Future<void> show(String path) =>
      channel.invokeMethod<void>('show', {'path': path});
  Future<void> cancelInstall(String path) =>
      channel.invokeMethod<void>('cancelInstall', {'path': path});
  Future<void> stop(String path, {bool force = false}) =>
      channel.invokeMethod<void>('stop', {'path': path, 'force': force});
  Future<void> completeInstallation(String path) =>
      channel.invokeMethod<void>('completeInstallation', {'path': path});
}

String nativeVmError(Object error) =>
    error is PlatformException ? error.message ?? error.code : '$error';
