import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'relative_path.dart';
import 'schema_location.dart';

/// Reads the `schema` value: an `http` or `https` URL, or a relative path.
final class const SchemaLocationReader() {
  /// Creates the reader.
  this;

  /// Returns the location [node] holds, or reports the problem and returns
  /// null.
  SchemaLocation? read(YamlNode node, ConfigReport report) {
    final text = report.string(node, 'schema');
    if (text == null) return null;
    final lower = text.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      final path = const RelativePath().read(node, 'schema', report);
      return path == null ? null : SchemaFile(path);
    }
    final url = Uri.tryParse(text);
    if (url == null || url.host.isEmpty) {
      report.error(node, "'schema' is not a valid URL.");
      return null;
    }
    return SchemaUrl(url);
  }
}
