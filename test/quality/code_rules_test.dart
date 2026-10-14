@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'code_rules.dart';
import 'workspace_files.dart';

/// The size ratchet and the pattern rules of `CLAUDE.md` ("Code rules")
/// over the whole workspace. Run `dart test` from the workspace root.
void main() {
  const rules = CodeRules();

  /// Files over their size limit for good: catalogs with no logic.
  const permanent = {
    'packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart',
  };

  /// Files over their size limit when they were listed, with their lines
  /// then; such a file may only shrink. Empty: keep it so.
  const fileAllowlist = <String, int>{};

  /// Methods over the limit when they were listed (`path#Type.member`),
  /// with their lines then. Empty: keep it so.
  const methodAllowlist = <String, int>{};

  final files = WorkspaceFiles(Directory.current.path).read();

  test('runs from the workspace root', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('workspace:'));
    expect(files.keys, contains('test/quality/code_rules_test.dart'));
  });

  test('no file breaks a rule that allows no exception', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        ...rules.violations(path, content),
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });

  test('no file is over its size limit, unless allowlisted and not grown', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        if (rules.oversizedFile(path, content) case final lines?)
          if (!permanent.contains(path) && lines > (fileAllowlist[path] ?? 0))
            '$path has $lines lines, over its limit; split it by '
                'responsibility, do not add it to the allowlist',
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });

  test('no method is over 40 lines, unless allowlisted and not grown', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        for (final MapEntry(key: method, value: lines)
            in rules.longMethods(path, content).entries)
          if (lines > (methodAllowlist[method] ?? 0))
            '$method has $lines lines, over ${CodeRules.methodLimit}; split '
                'it into named steps, do not add it to the allowlist',
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });
}
