import 'package:yaml/yaml.dart';

import 'config_report.dart';

/// Reads a path of the configuration: relative to the configuration file,
/// with `/` separators, and inside its folder.
final class const RelativePath() {
  /// Creates the reader.
  this;

  static final RegExp _driveLetter = RegExp('^[A-Za-z]:');

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
    if (path.startsWith('/') || _driveLetter.hasMatch(path)) {
      return 'must be a relative path.';
    }
    if (path.split('/').contains('..')) {
      return "must not have a '..' segment.";
    }
    return null;
  }
}
