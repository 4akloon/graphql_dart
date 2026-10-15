import 'package:yaml/yaml.dart';

import 'config_report.dart';

/// Reads the `headers` map: header names to raw string values.
final class const HeaderReader() {
  /// Creates the reader.
  this;

  static final RegExp _name = RegExp(r'^[^\s:]+$');

  /// Returns the headers of [node], sorted by name; the entries with problems
  /// are left out and reported.
  Map<String, String> read(YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(node, "'headers' must be a map of header names to strings.");
      return const {};
    }
    final headers = <String, String>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      final name = report.string(key, 'headers');
      if (name == null) continue;
      if (!_name.hasMatch(name)) {
        report.error(key, "'$name' is not a valid header name.");
        continue;
      }
      final text = report.string(value, 'headers.$name');
      if (text != null) headers[name] = text;
    }
    return {
      for (final name in headers.keys.toList()..sort()) name: headers[name]!,
    };
  }
}
