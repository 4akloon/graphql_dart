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

  /// One directive up to its `;`, so that the URIs of a conditional
  /// import (`if (dart.library.io) 'x.dart'`) are all found.
  static final RegExp _directive = RegExp(
    r'^(?:import|export)\s[^;]*;',
    multiLine: true,
  );

  static final RegExp _uri = RegExp(r'''['"]([^'"]+)['"]''');

  /// The violations in [content], the text of the library at [filePath].
  List<String> check(String filePath, String content) => [
    for (final directive in _directive.allMatches(content))
      for (final uri in _uri.allMatches(directive.group(0)!))
        ?_violation(filePath, uri.group(1)!),
  ];

  String? _violation(String filePath, String target) {
    if (target.startsWith('dart:')) {
      return _pureDart.contains(target)
          ? null
          : '$filePath imports $target: the client is platform independent';
    }
    if (target == 'package:meta/meta.dart' || _packages.contains(target)) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only package:meta/meta.dart and ${_packages.join(', ')} '
          'are allowed';
    }
    return _escapes(filePath, target)
        ? '$filePath imports $target, which leaves lib/'
        : null;
  }

  /// Whether the relative [target], read from [filePath], leaves `lib/`.
  bool _escapes(String filePath, String target) {
    final parts = [
      ...filePath.replaceAll(r'\\', '/').split('/').where((p) => p != '.'),
    ]..removeLast();
    for (final segment in target.split('/')) {
      if (segment == '..') {
        if (parts.length <= 1 || parts.last == 'lib') {
          return true;
        }
        parts.removeLast();
      } else if (segment != '.') {
        parts.add(segment);
      }
    }
    return !parts.contains('lib');
  }
}
