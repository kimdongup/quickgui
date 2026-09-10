import 'package:flutter/services.dart';

class AppleRestoreImage {
  AppleRestoreImage(Map<Object?, Object?> data)
    : version = data['version'] as String,
      build = data['build'] as String,
      minimumCPU = data['minimumCPU'] as int,
      maximumCPU = data['maximumCPU'] as int,
      minimumMemoryGiB = data['minimumMemoryGiB'] as int,
      maximumMemoryGiB = data['maximumMemoryGiB'] as int;
  final String version, build;
  final int minimumCPU, maximumCPU, minimumMemoryGiB, maximumMemoryGiB;
}

class AppleVmRecord {
  AppleVmRecord(Map<Object?, Object?> data)
    : path = data['path'] as String,
      name = data['name'] as String,
      state = data['state'] as String,
      error = data['error'] as String?,
      version = data['version'] as String? ?? '',
      progress = (data['progress'] as num?)?.toDouble().clamp(0, 1);
  final String path, name, state, version;
  final String? error;
  final double? progress;
  bool get canStart => state == 'stopped';
  bool get canShow => state == 'running' || state == 'stopping';
  bool get canCancel => state == 'installing';
  bool get canStop => state == 'running';
  bool get canForceStop => canShow || state == 'error';
  String get label => switch (state) {
    'installing' => 'Installing macOS',
    'cancelling' => 'Cancelling installation',
    'stopped' => 'Ready to run',
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

class AppleVmService {
  const AppleVmService({
    this.channel = const MethodChannel('quickgui/apple-vm'),
  });
  final MethodChannel channel;

  Future<bool> supported() async {
    try {
      return await channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<AppleRestoreImage> inspectImage(String path) async =>
      AppleRestoreImage(
        (await channel.invokeMapMethod<Object?, Object?>('inspectImage', {
          'path': path,
        }))!,
      );

  Future<AppleVmRecord> create({
    required String directory,
    required String name,
    required String ipsw,
    required int cpus,
    required int memoryGiB,
    required int diskGiB,
  }) async => AppleVmRecord(
    (await channel.invokeMapMethod<Object?, Object?>('create', {
      'directory': directory,
      'name': name,
      'ipsw': ipsw,
      'cpus': cpus,
      'memoryGiB': memoryGiB,
      'diskGiB': diskGiB,
    }))!,
  );

  Future<List<AppleVmRecord>> list(String directory) async => [
    for (final row in (await channel.invokeListMethod<Object?>('list', {
      'directory': directory,
    }))!)
      AppleVmRecord(row as Map<Object?, Object?>),
  ];
  Future<AppleVmRecord> status(String path) async => AppleVmRecord(
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
}

String appleVmError(Object error) =>
    error is PlatformException ? error.message ?? error.code : '$error';
