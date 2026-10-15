import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

/// One directory of `test/goldens/`: the input project, the generated files
/// it must produce and the extra files its analysis needs.
final class GoldenCase {
  /// The case in the directory [directory].
  GoldenCase(this.directory);

  /// Every case, sorted by name.
  static List<GoldenCase> all() => [
    for (final entity in Directory('test/goldens').listSync())
      if (entity is Directory) GoldenCase(entity),
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// The case's directory.
  final Directory directory;

  /// The directory's name.
  String get name => directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

  /// The configuration read from `input/typed_graphql.yaml`.
  CodegenConfig get config {
    final result = CodegenConfig.parse(
      File('${directory.path}/input/typed_graphql.yaml').readAsStringSync(),
      path: 'typed_graphql.yaml',
    );
    if (result is! ConfigSuccess) throw StateError('$name: $result');
    return result.config;
  }

  /// The input files by path relative to `input/`.
  Map<String, String> get inputs => _read('input', (path) => true);

  /// The schema file, at the path the configuration names.
  ProjectFile get schema {
    final location = config.schema;
    if (location is! SchemaFile) throw StateError('$name: needs a schema file');
    return ProjectFile(location.path, inputs[location.path] ?? '');
  }

  /// Every `.graphql` input but the schema.
  List<ProjectFile> get documents => [
    for (final path in inputs.keys.toList()..sort())
      if (path.endsWith('.graphql') && path != schema.path)
        ProjectFile(path, inputs[path]!),
  ];

  /// The generated files the case expects, by their path (the `.golden`
  /// suffix removed).
  Map<String, String> get goldens => _read(
    'output',
    (path) => path.endsWith('.golden'),
  ).map((path, text) => MapEntry(path.substring(0, path.length - 7), text));

  /// The extra files of the analysis package, by path (the `.txt` suffix
  /// removed).
  Map<String, String> get support => _read(
    'support',
    (path) => path.endsWith('.txt'),
  ).map((path, text) => MapEntry(path.substring(0, path.length - 4), text));

  /// Writes [files] as the case's goldens, replacing the old ones.
  void writeGoldens(List<GeneratedFile> files) {
    final output = Directory('${directory.path}/output');
    if (output.existsSync()) output.deleteSync(recursive: true);
    for (final file in files) {
      final target = File('${output.path}/${file.path}.golden');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.text);
    }
  }

  Map<String, String> _read(String folder, bool Function(String) isWanted) {
    final root = Directory('${directory.path}/$folder');
    if (!root.existsSync()) return {};
    final files = <String, String>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path
          .substring(root.path.length + 1)
          .replaceAll(r'\', '/');
      if (isWanted(path)) files[path] = entity.readAsStringSync();
    }
    return files;
  }
}
