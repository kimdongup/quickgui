import 'version.dart';

enum ArmMedia { windows, macos }

class OperatingSystem {
  OperatingSystem(this.name, this.code, {this.armMedia}) : versions = [];

  final String name;
  final String code;
  final ArmMedia? armMedia;
  List<Version> versions;

  String get displayName => switch (armMedia) {
    ArmMedia.windows => 'Windows — ARM64',
    ArmMedia.macos => 'macOS — Apple Silicon ARM64',
    null => switch (code) {
      'macos' => '$name — Intel x64',
      'windows' || 'windows-server' => '$name — x64',
      _ => name,
    },
  };

  /// The existing Windows/macOS Quickget paths provide x64 media only.
  String? get downloadArchitecture => armMedia != null
      ? 'arm64'
      : ['macos', 'windows', 'windows-server'].contains(code)
      ? 'amd64'
      : null;
}

Future<List<OperatingSystem>>? gOperatingSystems;
