import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/catalog.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/toolchain.dart';

void main() {
  test(
    'installed quickget catalog matches the parser contract',
    () async {
      final tools = Toolchain();
      final quickget =
          Platform.environment['QUICKGUI_TEST_QUICKGET'] ??
          tools.find('quickget');
      expect(quickget, isNotNull);
      final result = await const CommandRunner().run(
        quickget!,
        ['--list-csv'],
        directory: Directory.systemTemp.path,
        environment: tools.environment,
        timeout: const Duration(minutes: 3),
        outputLimit: 8 * 1024 * 1024,
      );
      result.requireSuccess();
      final systems = parseCatalog(result.stdout);
      expect(systems.length, greaterThan(20));
      expect(systems.every((os) => os.versions.isNotEmpty), isTrue);
    },
    skip: Platform.environment['QUICKGUI_REAL_CATALOG_TESTS'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
