import 'package:yaml/yaml.dart';

import 'config_report.dart';

/// Reads a path of the configuration: relative to the configuration file,
/// with `/` separators, and inside its folder.
final class const RelativePath() {
  /// Creates the reader.
  this;

  // Any scheme, a one-letter one included: paths are POSIX, so a drive
  // letter is not a path either.
  static final RegExp _scheme = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:');

  /// Returns the path [node] holds, or reports why it is not one named by
  /// [label] and returns null.
  String? read(YamlNode node, String label, ConfigReport report) {
    final path = report.string(node, label);
    if (path == null) return null;
    final problem = _problemOf(path);
    if (problem == null) return path;
    report.error(node, "'$label' $problem");
    return null;
  }

  String? _problemOf(String path) {
    if (path.isEmpty) return 'must not be empty.';
    if (path.contains(r'\')) return "must use '/' as the separator.";
    if (path.startsWith('/') ||
        path.contains('://') ||
        _scheme.hasMatch(path)) {
      return 'must be a relative path.';
    }
    final segments = path.split('/');
    if (segments.contains('..')) {
      return "must not have a '..' segment.";
    }
    if (segments.last.isEmpty || segments.last == '.') {
      return 'must name a file.';
    }
    return null;
  }
}
