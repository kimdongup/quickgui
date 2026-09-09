import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/src/services/command_runner.dart';
import 'package:quickgui/src/services/toolchain.dart';

void main() {
  List<String> path(String? inherited, {bool macOS = true}) => Toolchain(
    environment: {'PATH': ?inherited},
    isMacOS: macOS,
  ).environment['PATH']!.split(':');

  for (final system in ['/bin', '/usr/bin', '/usr/sbin', '/sbin']) {
    test('macOS places Homebrew before inherited $system', () {
      final entries = path('$system:/opt/homebrew/bin:/usr/local/bin');
      expect(
        entries.indexOf('/opt/homebrew/bin'),
        lessThan(entries.indexOf(system)),
      );
      expect(
        entries.indexOf('/usr/local/bin'),
        lessThan(entries.indexOf(system)),
      );
      expect(entries.where((e) => e == '/opt/homebrew/bin'), hasLength(1));
      expect(entries.where((e) => e == '/usr/local/bin'), hasLength(1));
    });
  }

  test('macOS retains leading custom tools and the remaining PATH order', () {
    final entries = path('/custom tools/bin:/bin:/another/bin:/usr/bin');
    expect(entries.take(6), [
      '/custom tools/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/bin',
      '/another/bin',
      '/usr/bin',
    ]);
  });

  test('an already leading Homebrew prefix stays ahead of custom tools', () {
    expect(path('/opt/homebrew/bin:/custom/bin:/bin').take(4), [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/custom/bin',
      '/bin',
    ]);
  });

  test(
    'missing and empty macOS PATH still prefer Homebrew to system tools',
    () {
      for (final inherited in [null, '', '::']) {
        final entries = path(inherited);
        expect(
          entries.indexOf('/opt/homebrew/bin'),
          lessThan(entries.indexOf('/bin')),
        );
        expect(
          entries.indexOf('/usr/local/bin'),
          lessThan(entries.indexOf('/usr/bin')),
        );
        expect(entries, isNot(contains('')));
      }
    },
  );

  test('Linux keeps the inherited PATH order', () {
    expect(
      path(
        '/bin:/custom/bin:/opt/homebrew/bin:/usr/local/bin',
        macOS: false,
      ).take(4),
      ['/bin', '/custom/bin', '/opt/homebrew/bin', '/usr/local/bin'],
    );
  });

  test('construction does not mutate the caller environment', () {
    final inherited = {'PATH': '/bin:/usr/bin', 'HOME': '/custom home'};
    final tools = Toolchain(environment: inherited, isMacOS: true);
    expect(inherited, {'PATH': '/bin:/usr/bin', 'HOME': '/custom home'});
    expect(tools.environment['HOME'], '/custom home');
  });

  test(
    'env shebang and nested Bash use Homebrew with a system-first parent PATH',
    () async {
      final tmp = await Directory.systemTemp.createTemp('quickgui-bash-');
      addTearDown(() => tmp.delete(recursive: true));
      final script = File('${tmp.path}/backend with spaces');
      await script.writeAsString(r'''#!/usr/bin/env bash
if (( BASH_VERSINFO[0] < 4 )); then
  echo 'Sorry, you need bash 4.0 or newer to run this script.' >&2
  exit 1
fi
printf '%s\n' "$BASH"
/usr/bin/env bash -c '(( BASH_VERSINFO[0] >= 4 )) || exit 1; printf "%s\n" "$BASH" "$1"' -- "$1"
''');
      expect(
        (await Process.run('/bin/chmod', ['+x', script.path])).exitCode,
        0,
      );
      final tools = Toolchain(
        environment: {
          ...Platform.environment,
          'PATH': '/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin',
        },
      );
      const argument = r'a value; $(not-a-command)';
      final result = await const CommandRunner().run(
        script.path,
        [argument],
        directory: tmp.path,
        environment: tools.environment,
      );
      expect(result.exitCode, 0, reason: result.message);
      expect(result.stdout.trim().split('\n'), [
        tools.find('bash'),
        tools.find('bash'),
        argument,
      ]);
    },
    skip:
        !Platform.isMacOS ||
        ![
          '/opt/homebrew/bin/bash',
          '/usr/local/bin/bash',
        ].any((p) => File(p).existsSync()),
  );

  test(
    'installed backends run with system-first and minimal macOS PATHs',
    () async {
      for (final inherited in [
        '/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin',
        '/usr/bin:/bin:/usr/sbin:/sbin',
      ]) {
        final tools = Toolchain(
          environment: {...Platform.environment, 'PATH': inherited},
        );
        for (final name in ['quickemu', 'quickget']) {
          final executable = tools.find(name);
          expect(executable, isNotNull, reason: '$name with PATH=$inherited');
          final result = await const CommandRunner().run(
            executable!,
            ['--version'],
            directory: Directory.systemTemp.path,
            environment: tools.environment,
          );
          expect(result.exitCode, 0, reason: '$name: ${result.message}');
          expect(result.stdout.trim(), matches(r'^\d+\.\d+\.\d+'));
        }
      }
    },
    skip:
        !Platform.isMacOS ||
        Platform.environment['QUICKGUI_REAL_CATALOG_TESTS'] != '1',
  );
}
