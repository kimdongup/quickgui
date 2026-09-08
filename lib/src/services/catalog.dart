import '../model/operating_system.dart';
import '../model/version.dart';
import '../model/option.dart';

/// Parse quoted CSV fields, including commas, newlines and escaped quotes.
List<List<String>> csvRows(String input) {
  final rows = <List<String>>[], row = <String>[];
  var field = StringBuffer(), quoted = false;
  input = input.replaceFirst(RegExp(r'^\uFEFF'), '');
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == ',' || c == '\n' || c == '\r')) {
      row.add(field.toString());
      field = StringBuffer();
      if (c != ',') {
        if (row.any((s) => s.trim().isNotEmpty)) rows.add(List.of(row));
        row.clear();
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      }
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote');
  row.add(field.toString());
  if (row.any((s) => s.trim().isNotEmpty)) rows.add(row);
  return rows;
}

List<OperatingSystem> parseCatalog(String input) {
  final rows = csvRows(input);
  if (rows.isEmpty) return [];
  if (rows.first.length < 4 || rows.first[1].toLowerCase() != 'os') {
    throw const FormatException('Unrecognized quickget CSV header');
  }
  final systems = <String, OperatingSystem>{};
  for (final row in rows.skip(1)) {
    if (![4, 5, 7].contains(row.length) ||
        row.take(3).any((s) => s.trim().isEmpty)) {
      throw const FormatException('Invalid quickget CSV row');
    }
    final os = systems.putIfAbsent(
      row[1],
      () => OperatingSystem(row[0], row[1]),
    );
    final version =
        os.versions.where((v) => v.version == row[2]).firstOrNull ??
        Version(row[2]);
    if (!os.versions.contains(version)) os.versions.add(version);
    final downloader = row.length == 4 || row[4].isEmpty ? 'curl' : row[4];
    if (!version.options.any((o) => o.option == row[3])) {
      version.options.add(Option(row[3], downloader));
    }
  }
  return systems.values.toList();
}
