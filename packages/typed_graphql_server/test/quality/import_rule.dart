/// The server's import rules (spec 2 and 17.4, R0.6), checked on the text of
/// one library under `lib/`.
///
/// The server runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
/// Dart, `dart:convert`, `dart:typed_data` (the bytes of a request body),
/// `meta`, `package:crypto/crypto.dart` (SHA-256 of
/// documents), `package:mime/mime.dart` (the multipart parser), the core's barrel and its own files, never `src/` of the core
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
    'dart:typed_data',
  };

  static const String _crypto = 'package:crypto/crypto.dart';

  static const String _mime = 'package:mime/mime.dart';

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
        target == _crypto ||
        target == _mime) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only meta, crypto, mime and the '
          'core barrel ($_coreBarrel) are allowed';
    }
    return null;
  }
}
