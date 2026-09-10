import '../model/operating_system.dart';
import '../model/option.dart';
import '../model/version.dart';

List<String> quickgetDownloadArguments(
  OperatingSystem os,
  Version version,
  Option? option,
  List<String> defaults,
) {
  if (os.armMedia != null) {
    throw ArgumentError('ARM media uses its own downloader.');
  }
  return [
    if (os.downloadArchitecture case final String architecture) ...[
      '--arch',
      architecture,
    ] else
      ...defaults,
    os.code,
    version.version,
    if (option?.option.isNotEmpty ?? false) option!.option,
  ];
}

/// Personal media downloads are separate from Quickget's VM creation catalog.
List<OperatingSystem> withArmMedia(List<OperatingSystem> catalog) {
  OperatingSystem media(
    String name,
    String code,
    ArmMedia kind,
    String release,
  ) =>
      OperatingSystem(name, code, armMedia: kind)
        ..versions.add(Version(release)..options.add(Option('', 'official')));
  return [
    ...catalog,
    media('macOS', 'macos', ArmMedia.macos, 'Latest compatible'),
    media('Windows', 'windows', ArmMedia.windows, '11'),
  ]..sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
}
