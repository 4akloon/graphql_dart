/// The client's import rules (spec section 2, R0.5), checked on the text of
/// one library under `lib/`.
///
/// The client runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
/// Dart, `meta`, the core's barrel and its own files, never `src/` of the
/// core, never `dart:io` or a web-only library.
final class ImportRule {
  /// Creates the rule.
  const ImportRule();

  /// The libraries that run on every platform the client supports.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:math',
    'dart:typed_data',
  };

  /// The package libraries the client may import.
  static const Set<String> _packages = {
    'package:typed_graphql/typed_graphql.dart',
  };

  static final RegExp _directive = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// The violations in [content], the text of the library at [filePath].
  List<String> check(String filePath, String content) => [
    for (final match in _directive.allMatches(content))
      ?_violation(filePath, match.group(1)!),
  ];

  String? _violation(String filePath, String target) {
    if (target.startsWith('dart:')) {
      return _pureDart.contains(target)
          ? null
          : '$filePath imports $target: the client is platform independent';
    }
    if (target.startsWith('package:meta/') || _packages.contains(target)) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only meta and ${_packages.join(', ')} '
          'are allowed';
    }
    return null;
  }
}
