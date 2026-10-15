import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../config/config_result.dart';
import '../config/schema_location.dart';
import '../project/project_file.dart';
import 'project_read_result.dart';

/// Reads the configuration, the schema file and the documents of a project
/// from disk.
///
/// {@category codegen}
final class const ProjectReader(
  /// The directory of the configuration file; every path is relative to it.
  final String directory,
) {
  /// Creates a reader for the project in [directory].
  this;

  /// Reads the project whose configuration is the file [configName].
  ProjectReadResult read(String configName) {
    final configText = _readText(configName);
    if (configText is _Failed) return ProjectReadFailed([configText.problem]);
    final parsed = CodegenConfig.parse(
      (configText as _Text).text,
      path: configName,
    );
    if (parsed is ConfigFailure) return ProjectReadFailed(parsed.diagnostics);
    final config = (parsed as ConfigSuccess).config;
    final location = config.schema;
    if (location is! SchemaFile) {
      return ProjectReadFailed([
        _unreadable(
          '${location is SchemaUrl ? location.url : location}',
          'Fetching a schema URL is not supported here.',
        ),
      ]);
    }
    return _readSources(config, location.path);
  }

  ProjectReadResult _readSources(CodegenConfig config, String schemaPath) {
    final schema = _readText(schemaPath);
    if (schema is _Failed) return ProjectReadFailed([schema.problem]);
    final problems = <Diagnostic>[];
    final documents = <ProjectFile>[];
    for (final path in _documentPaths(config, schemaPath)) {
      final text = _readText(path);
      switch (text) {
        case _Text():
          documents.add(ProjectFile(path, text.text));
        case _Failed():
          problems.add(text.problem);
      }
    }
    if (problems.isNotEmpty) return ProjectReadFailed(problems);
    return ProjectRead(
      config,
      ProjectFile(schemaPath, (schema as _Text).text),
      documents,
    );
  }

  List<String> _documentPaths(CodegenConfig config, String schemaPath) {
    final paths = <String>{};
    for (final pattern in config.documents) {
      for (final entity in Glob(pattern).listSync(root: directory)) {
        if (entity is! File || !entity.path.endsWith('.graphql')) continue;
        final relative = p.posix.joinAll(
          p.split(p.relative(entity.path, from: directory)),
        );
        if (relative != schemaPath) paths.add(relative);
      }
    }
    return paths.toList()..sort();
  }

  _ReadOutcome _readText(String path) {
    try {
      return _Text(File(p.join(directory, path)).readAsStringSync());
    } on FileSystemException catch (error) {
      return _Failed(
        _unreadable(path, error.osError?.message ?? error.message),
      );
    } on FormatException catch (error) {
      return _Failed(_unreadable(path, error.message));
    }
  }

  Diagnostic _unreadable(String path, String reason) => Diagnostic(
    .inputUnreadable,
    .error,
    "Cannot read '$path': $reason.",
  );
}

sealed class _ReadOutcome {
  const _ReadOutcome();
}

final class _Text extends _ReadOutcome {
  const _Text(this.text);
  final String text;
}

final class _Failed extends _ReadOutcome {
  const _Failed(this.problem);
  final Diagnostic problem;
}
