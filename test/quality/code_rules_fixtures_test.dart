import 'package:test/test.dart';

import 'code_rules.dart';

/// Every rule of [CodeRules] on a small file that breaks it, and on one
/// that keeps it.
void main() {
  const rules = CodeRules();
  const libPath = 'packages/p/lib/src/a.dart';
  const testPath = 'packages/p/test/a_test.dart';

  List<String> violations(String path, String content) =>
      rules.violations(path, content);

  /// A class `A` whose body is [body].
  String classWith(String body) => '/// A.\nfinal class A {\n$body}\n';

  group('pattern rules', () {
    test('a clean file has no violations', () {
      expect(
        violations(libPath, classWith('  int get x => 1;\n')),
        isEmpty,
      );
    });

    test('part directives are rejected', () {
      expect(violations(libPath, "part 'b.dart';\n"), [
        '$libPath:1: a part directive; split into libraries',
      ]);
    });

    test('dynamic is rejected in code but not in comments or strings', () {
      expect(
        violations(testPath, 'void main() {\n  dynamic x;\n}\n'),
        ['$testPath:2: dynamic; use Object? or a real type'],
      );
      expect(
        violations(testPath, "// dynamic\nvoid main() => print('dynamic');\n"),
        isEmpty,
      );
    });

    test('a catch without on is rejected', () {
      expect(
        violations(
          testPath,
          'void main() {\n  try {\n  } catch (e) {\n  }\n}\n',
        ),
        ['$testPath:3: a catch without on; name the exception'],
      );
      expect(
        violations(
          testPath,
          'void main() {\n  try {\n  } on FormatException catch (e) {\n  }\n'
          '  f().catchError(g);\n}\n',
        ),
        isEmpty,
      );
    });

    test('top-level functions other than main are rejected', () {
      expect(
        violations(testPath, 'void main() {\n  int local() => 1;\n}\n'),
        isEmpty,
      );
      expect(violations(testPath, 'int helper() => 1;\n'), [
        '$testPath:1: the top-level function helper; put it in a class',
      ]);
      expect(violations(libPath, 'int get answer => 42;\n'), hasLength(1));
    });

    test('utils and helpers files are rejected in lib only', () {
      for (final path in [
        'packages/p/lib/src/utils.dart',
        'packages/p/lib/src/string_helpers.dart',
        'packages/p/lib/src/common/a.dart',
      ]) {
        expect(violations(path, ''), hasLength(1), reason: path);
      }
      expect(violations('packages/p/test/helpers/temp_dir.dart', ''), isEmpty);
      expect(
        violations('packages/typed_graphql_common/lib/a.dart', ''),
        isEmpty,
      );
    });

    test('control blocks nested deeper than 3 are rejected', () {
      const deep =
          'void main() {\n'
          '  for (;;) {\n'
          '    if (a) {\n'
          '      while (b) {\n'
          '        if (c) {}\n'
          '      }\n'
          '    }\n'
          '  }\n'
          '}\n';
      expect(violations(testPath, deep), [
        '$testPath:5: control blocks nest deeper than 3; return early or extract '
            'a method',
      ]);
    });

    test('methods in lib take at most 5 parameters, constructors any', () {
      expect(
        violations(
          libPath,
          classWith('  void f(int a, int b, int c, int d, int e, int f) {}\n'),
        ),
        [
          '$libPath:3: A.f takes 6 parameters, over 5; take a parameter object',
        ],
      );
      expect(
        violations(
          libPath,
          classWith('  A(int a, int b, int c, int d, int e, int f);\n'),
        ),
        isEmpty,
      );
    });

    test('a file in lib declares one public class or sealed family', () {
      expect(
        violations(
          libPath,
          '/// A.\nfinal class A {}\n\n/// B.\nfinal class B {}\n',
        ),
        [
          '$libPath:1: A, B are separate public types; keep one public class or '
              'sealed family per file',
        ],
      );
      expect(
        violations(
          libPath,
          'sealed class R {}\n\nfinal class S(int v)\n    extends R;\n\n'
          'final class F extends R {}\n\nfinal class _Helper {}\n',
        ),
        isEmpty,
      );
    });

    test('paths with Windows separators are read', () {
      expect(
        violations(r'packages\p\lib\src\utils.dart', "part 'b.dart';\n"),
        [
          'packages/p/lib/src/utils.dart:1: a part directive; split into '
              'libraries',
          'packages/p/lib/src/utils.dart:1: a utils or helpers file; name it '
              'after what it does',
        ],
      );
    });
  });

  group('size measurements', () {
    String lines(int count) => List.filled(count, '// line\n').join();

    test('a file in lib may have 300 lines, a test 500', () {
      expect(rules.oversizedFile(libPath, lines(300)), isNull);
      expect(rules.oversizedFile(libPath, lines(301)), 301);
      expect(rules.oversizedFile(testPath, lines(500)), isNull);
      expect(
        rules.oversizedFile(r'packages\p\test\a_test.dart', lines(501)),
        501,
      );
    });

    test('a method in lib may have 40 lines', () {
      String method(int bodyLines) =>
          classWith('  void run() {\n${'    f();\n' * bodyLines}  }\n');
      expect(rules.longMethods(libPath, method(38)), isEmpty);
      expect(rules.longMethods(libPath, method(39)), {'$libPath#A.run': 41});
      expect(rules.longMethods(testPath, method(39)), isEmpty);
    });

    test('an arrow body counts, a long field initializer does not', () {
      expect(
        rules.longMethods(
          libPath,
          classWith('  List<int> get all => [\n${'    1,\n' * 45}  ];\n'),
        ),
        {'$libPath#A.all': 47},
      );
      expect(
        rules.longMethods(
          libPath,
          classWith('  static const all = [\n${'    1,\n' * 45}  ];\n'),
        ),
        isEmpty,
      );
    });
  });
}
