import 'dart_writer.dart';

/// Collects the imports of one generated library and writes them in
/// `directives_ordering` order.
///
/// {@category codegen}
final class Imports {
  /// Creates an empty collection.
  Imports();

  final List<_Import> _dart = <_Import>[];
  final List<_Import> _package = <_Import>[];
  final List<_Import> _relative = <_Import>[];
  final Map<String, String> _scalarPrefixes = <String, String>{};

  /// Records `import '[uri]'` of a `dart:` or `package:` library.
  void package(String uri, {String? prefix}) {
    _add(uri.startsWith('dart:') ? _dart : _package, _Import(uri, prefix));
  }

  /// Records `import '[path]'` of a library of the same package.
  void relative(String path, {String? prefix}) {
    _add(_relative, _Import(path, prefix));
  }

  /// The prefix of the custom scalar library [uri], recorded as an import.
  ///
  /// Prefixes are `scalar_0`, `scalar_1`, ... in order of first request.
  String prefixFor(String uri) {
    final String? known = _scalarPrefixes[uri];
    if (known != null) {
      return known;
    }
    final String prefix = 'scalar_${_scalarPrefixes.length}';
    _scalarPrefixes[uri] = prefix;
    package(uri, prefix: prefix);
    return prefix;
  }

  /// Writes the imports, `dart:` first, then `package:`, then relative.
  void write(DartWriter writer) {
    bool isFirst = true;
    for (final List<_Import> group in <List<_Import>>[
      _dart,
      _package,
      _relative,
    ]) {
      if (group.isEmpty) {
        continue;
      }
      if (!isFirst) {
        writer.line();
      }
      isFirst = false;
      final List<_Import> sorted = <_Import>[...group]..sort(_Import.compare);
      for (final _Import import in sorted) {
        writer.line(import.text);
      }
    }
  }

  void _add(List<_Import> group, _Import import) {
    if (!group.contains(import)) {
      group.add(import);
    }
  }
}

final class _Import {
  const _Import(this.uri, this.prefix);

  final String uri;
  final String? prefix;

  String get text =>
      prefix == null ? "import '$uri';" : "import '$uri' as $prefix;";

  static int compare(_Import a, _Import b) {
    final int byUri = a.uri.compareTo(b.uri);
    return byUri != 0 ? byUri : (a.prefix ?? '').compareTo(b.prefix ?? '');
  }

  @override
  bool operator ==(Object other) =>
      other is _Import && other.uri == uri && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(uri, prefix);
}
