import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'dart_reference.dart';
import 'dart_reference_reader.dart';
import 'scalar_mapping.dart';

/// Reads the `scalars` map: scalar names to their Dart type and codec.
final class const ScalarMappingReader() {
  /// Creates the reader.
  this;

  static final RegExp _name = RegExp(r'^[_A-Za-z][_0-9A-Za-z]*$');

  /// Returns the mappings of [node], sorted by scalar name; the entries with
  /// problems are left out and reported.
  Map<String, ScalarMapping> read(YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(node, "'scalars' must be a map of scalar names.");
      return const {};
    }
    final mappings = <String, ScalarMapping>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      final text = report.keyText(key);
      if (text == null || !_name.hasMatch(text)) {
        report.error(key, 'A scalar name must be a GraphQL name.');
        continue;
      }
      final mapping = _readMapping(text, value, report);
      if (mapping != null) mappings[text] = mapping;
    }
    return {
      for (final name in mappings.keys.toList()..sort()) name: mappings[name]!,
    };
  }

  ScalarMapping? _readMapping(String name, YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(
        node,
        "Scalar '$name' must be a map with 'type' and 'codec'.",
      );
      return null;
    }
    DartReference? type;
    DartReference? codec;
    var isValid = true;
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      switch (report.keyText(key)) {
        case 'type':
          type = const DartReferenceReader().read(
            value,
            'type',
            report,
            isBareCoreAllowed: true,
          );
          isValid = isValid && type != null;
        case 'codec':
          codec = _readCodec(value, report);
          isValid = isValid && codec != null;
        default:
          report.error(
            key,
            "Scalar '$name' has the unknown key '${key.span.text}'; the keys "
            "are 'codec' and 'type'.",
          );
          isValid = false;
      }
    }
    isValid = _hasRequiredKeys(name, node, report) && isValid;
    if (isValid && type != null && codec != null) {
      return ScalarMapping(type, codec);
    }
    return null;
  }

  bool _hasRequiredKeys(String name, YamlMap node, ConfigReport report) {
    var hasAll = true;
    for (final key in ['type', 'codec']) {
      if (!node.containsKey(key)) {
        report.error(node, "Scalar '$name' needs a '$key'.");
        hasAll = false;
      }
    }
    return hasAll;
  }

  DartReference? _readCodec(YamlNode value, ConfigReport report) {
    final codec = const DartReferenceReader().read(
      value,
      'codec',
      report,
      isBareCoreAllowed: false,
    );
    if (codec != null && codec.library == null) {
      report.error(value, "'codec' must name a library.");
      return null;
    }
    return codec;
  }
}
