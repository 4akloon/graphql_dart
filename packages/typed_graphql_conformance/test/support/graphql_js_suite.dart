import 'dart:io';

/// The tests of one graphql-js test file in `reference/` (fetched by
/// `tool/fetch_reference.sh`, absent in CI): each `it` with the path of
/// the `describe` blocks around it, joined by ` > `.
final class GraphqlJsSuite {
  /// Reads `src/language/__tests__/[file]` of the fetched graphql-js.
  factory GraphqlJsSuite.read(String file) =>
      GraphqlJsSuite.parse(File('$directory/$file').readAsStringSync());

  /// Finds the tests in [source], a graphql-js test file formatted by
  /// Prettier: a block's indentation says which `describe` holds it.
  factory GraphqlJsSuite.parse(String source) {
    final groups = <(int, String)>[];
    final tests = <(String, String)>[];
    for (final line in source.split('\n')) {
      final match = _block.firstMatch(line);
      if (match?.groups([1, 2, 3]) case [
        final indent?,
        final kind?,
        final name?,
      ]) {
        groups.removeWhere((group) => group.$1 >= indent.length);
        if (kind == 'describe') {
          groups.add((indent.length, name));
        } else {
          tests.add((groups.map((group) => group.$2).join(' > '), name));
        }
      }
    }
    return GraphqlJsSuite._(tests);
  }

  GraphqlJsSuite._(this.tests);

  /// The language tests of graphql-js, relative to a package directory.
  static const String directory =
      '../../reference/graphql-js/src/language/__tests__';

  /// Whether graphql-js was fetched into `reference/`.
  static bool get isAvailable => Directory(directory).existsSync();

  /// The names of the test files in [directory], sorted; empty when
  /// graphql-js was not fetched.
  static List<String> get files {
    if (!isAvailable) {
      return const [];
    }
    return [
      for (final entity in Directory(directory).listSync())
        if (entity is File && entity.path.endsWith('.ts'))
          entity.uri.pathSegments.last,
    ]..sort();
  }

  static final RegExp _block = RegExp(r"^(\s*)(describe|it)\('([^']*)'");

  /// Each test as its group path and its name, in file order.
  final List<(String, String)> tests;
}
