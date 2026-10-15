import 'package:typed_graphql/typed_graphql.dart';
import 'package:yaml/yaml.dart';

/// Collects the `GQL501` problems of one configuration read, in the order the
/// reader meets the nodes.
final class ConfigReport(
  /// The text of the configuration file.
  final Source source,
) {
  /// Creates an empty report over [source].
  this;

  /// The problems reported so far.
  final List<Diagnostic> diagnostics = [];

  /// Whether no problem was reported.
  bool get isClean => diagnostics.isEmpty;

  /// The place of [node] in the configuration file.
  SourceSpan spanOf(YamlNode node) =>
      SourceSpan(source, node.span.start.offset, node.span.end.offset);

  /// Reports [message] at [node].
  void error(YamlNode node, String message) {
    diagnostics.add(
      Diagnostic(
        .invalidConfig,
        .error,
        message,
        span: spanOf(node),
      ),
    );
  }

  /// Returns the string [node] holds, or reports that [label] must be a
  /// string and returns null.
  String? string(YamlNode node, String label) {
    if (node case YamlScalar(value: final String value)) return value;
    error(node, "'$label' must be a string.");
    return null;
  }

  /// Returns the text of a map key, or null when it is not a string.
  String? keyText(YamlNode key) {
    if (key case YamlScalar(value: final String value)) return value;
    return null;
  }
}
