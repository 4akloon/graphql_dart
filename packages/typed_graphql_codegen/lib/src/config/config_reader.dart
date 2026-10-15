import 'package:typed_graphql/typed_graphql.dart';
import 'package:yaml/yaml.dart';

import 'codegen_config.dart';
import 'config_draft.dart';
import 'config_report.dart';
import 'config_result.dart';
import 'header_reader.dart';
import 'relative_path.dart';
import 'scalar_mapping_reader.dart';
import 'schema_location.dart';
import 'schema_location_reader.dart';

/// Turns the text of `typed_graphql.yaml` into a [ConfigResult].
final class ConfigReader(
  /// The configuration file's text and name.
  final Source source,
) {
  /// Creates a reader of [source].
  this;

  static const List<String> _keys = [
    'documents',
    'headers',
    'persisted_operations',
    'scalars',
    'schema',
    'schema_types',
  ];

  /// Reads [text], the body of [source].
  ConfigResult read(String text) {
    final YamlNode root;
    try {
      root = loadYamlNode(text);
    } on YamlException catch (error) {
      final start = error.span?.start.offset ?? 0;
      final end = error.span?.end.offset ?? 0;
      return ConfigFailure([
        Diagnostic(
          .configSyntax,
          .error,
          error.message,
          span: SourceSpan(source, start, end),
        ),
      ]);
    }
    final report = ConfigReport(source);
    final config = _readRoot(root, report);
    if (config == null || !report.isClean) {
      return ConfigFailure(report.diagnostics);
    }
    return ConfigSuccess(config);
  }

  CodegenConfig? _readRoot(YamlNode root, ConfigReport report) {
    if (root is! YamlMap) {
      report.error(root, 'The configuration must be a YAML map.');
      return null;
    }
    final draft = ConfigDraft();
    for (final MapEntry(:key, :value) in root.nodes.entries) {
      if (key is YamlNode) _readEntry(draft, key, value, report);
    }
    final headersKey = draft.headersKey;
    if (draft.schema is SchemaFile && headersKey != null) {
      report.error(headersKey, "'headers' apply only to a schema URL.");
    }
    if (!root.containsKey('schema')) {
      report.error(root, "The key 'schema' is required.");
    }
    return draft.build();
  }

  void _readEntry(
    ConfigDraft draft,
    YamlNode key,
    YamlNode value,
    ConfigReport report,
  ) {
    switch (report.keyText(key)) {
      case 'schema':
        draft.schema = const SchemaLocationReader().read(value, report);
      case 'documents':
        draft.documents = _readDocuments(value, report) ?? draft.documents;
      case 'schema_types':
        draft.schemaTypes =
            _readSuffixed(value, 'schema_types', '.dart', report) ??
            draft.schemaTypes;
      case 'persisted_operations':
        draft.persistedOperations = _readSuffixed(
          value,
          'persisted_operations',
          '.json',
          report,
        );
      case 'scalars':
        draft.scalars = const ScalarMappingReader().read(value, report);
      case 'headers':
        draft.headersKey = key;
        draft.headers = const HeaderReader().read(value, report);
      default:
        report.error(
          key,
          "Unknown key '${key.span.text}'; the keys are "
          "${_keys.map((name) => "'$name'").join(', ')}.",
        );
    }
  }

  List<String>? _readDocuments(YamlNode node, ConfigReport report) {
    if (node is! YamlList) {
      final path = const RelativePath().read(node, 'documents', report);
      return path == null ? null : [path];
    }
    if (node.nodes.isEmpty) {
      report.error(node, "'documents' must not be an empty list.");
      return null;
    }
    final paths = <String>[];
    for (final item in node.nodes) {
      final path = const RelativePath().read(item, 'documents', report);
      if (path != null) paths.add(path);
    }
    return paths;
  }

  String? _readSuffixed(
    YamlNode node,
    String label,
    String suffix,
    ConfigReport report,
  ) {
    final path = const RelativePath().read(node, label, report);
    if (path == null) return null;
    if (path.endsWith(suffix)) return path;
    report.error(node, "'$label' must end with '$suffix'.");
    return null;
  }
}
