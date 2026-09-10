import 'package:flutter/services.dart';

class InstallationFile {
  InstallationFile(Map<Object?, Object?> row)
    : path = row['path'] as String,
      name = row['name'] as String,
      kind = row['kind'] as String,
      bytes = row['bytes'] as int;
  final String path, name, kind;
  final int bytes;
}

class StorageDeletionPreview {
  StorageDeletionPreview(Map<Object?, Object?> row)
    : path = row['path'] as String,
      name = row['name'] as String,
      token = row['token'] as String,
      bytes = row['bytes'] as int,
      isVM = row['isVM'] as bool;
  final String path, name, token;
  final int bytes;
  final bool isVM;
}

class NativeStorageService {
  const NativeStorageService({
    this.channel = const MethodChannel('quickgui/native-storage'),
  });
  final MethodChannel channel;

  Future<List<InstallationFile>> listMedia(String directory) async => [
    for (final row in (await channel.invokeListMethod<Object?>('listMedia', {
      'directory': directory,
    }))!)
      InstallationFile(row as Map<Object?, Object?>),
  ];

  Future<void> addMedia(String path) =>
      channel.invokeMethod<void>('addMedia', {'path': path});

  Future<StorageDeletionPreview> preview({
    required String path,
    required String directory,
    required bool isVM,
  }) async => StorageDeletionPreview(
    (await channel.invokeMapMethod<Object?, Object?>('preview', {
      'path': path,
      'directory': directory,
      'isVM': isVM,
    }))!,
  );

  Future<void> delete(
    StorageDeletionPreview preview, {
    required String directory,
  }) => channel.invokeMethod<void>('delete', {
    'path': preview.path,
    'directory': directory,
    'isVM': preview.isVM,
    'token': preview.token,
  });
}

String storageSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}
