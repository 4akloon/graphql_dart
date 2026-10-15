/// The server's import rules (spec 2 and 17.4, R0.6), checked on the text of
/// one library under `lib/`.
///
/// The server runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
/// Dart, `dart:convert`, `meta`, `package:crypto/crypto.dart` (SHA-256 of
/// documents), the core's barrel and its own files, never `src/` of the core
/// and never a web framework.
final class ImportRule {
  /// Creates the rule.
  const ImportRule();

  /// The libraries that run on every platform the server supports.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:math',
  };

  static const String _crypto = 'package:crypto/crypto.dart';

  static const String _coreBarrel = 'package:typed_graphql/typed_graphql.dart';

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
          : '$filePath imports $target: the server is platform independent';
    }
    if (target.startsWith('package:meta/') ||
        target == _coreBarrel ||
        target == _crypto) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only meta, crypto and the core '
          'barrel ($_coreBarrel) are allowed';
    }
    return null;
  }
}
