import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../config/config_result.dart';
import '../config/schema_location.dart';
import '../project/project_file.dart';
import 'header_expander.dart';
import 'project_read_result.dart';
import 'schema_fetch_result.dart';
import 'schema_fetcher.dart';

/// Reads the configuration, the schema file and the documents of a project
/// from disk.
///
/// {@category codegen}
final class ProjectReader {
  /// Creates a reader for the project in [directory]; [environment] feeds the
  /// `${NAME}` references of the headers and [fetcher] gets a schema URL.
  const ProjectReader(
    this.directory, {
    this.environment = const {},
    this.fetcher = const SchemaFetcher(),
  });

  /// The directory of the configuration file; every path is relative to it.
  final String directory;

  /// The environment variables the header values may reference.
  final Map<String, String> environment;

  /// What fetches the schema of a configuration with a `schema` URL.
  final SchemaFetcher fetcher;

  /// Reads the project whose configuration is the file [configName].
  Future<ProjectReadResult> read(String configName) async {
    final configText = _readText(configName);
    if (configText is! _FileText) {
      return ProjectReadFailed([(configText as _FileFailed).problem]);
    }
    final parsed = CodegenConfig.parse(configText.text, path: configName);
    if (parsed is ConfigFailure) return ProjectReadFailed(parsed.diagnostics);
    final config = (parsed as ConfigSuccess).config;
    final schema = await _readSchema(config);
    return switch (schema) {
      _Text(:final file) => _readSources(config, file),
      _Failed(:final problems) => ProjectReadFailed(problems),
    };
  }

  Future<_SchemaOutcome> _readSchema(CodegenConfig config) async {
    switch (config.schema) {
      case SchemaFile(:final path):
        final text = _readText(path);
        return switch (text) {
          _FileText() => _Text(ProjectFile(path, text.text)),
          _FileFailed() => _Failed([text.problem]),
        };
      case SchemaUrl(:final url):
        final expansion = HeaderExpander(environment).expand(config.headers);
        if (expansion.problems.isNotEmpty) return _Failed(expansion.problems);
        return switch (await fetcher.fetch(url, expansion.headers)) {
          SchemaFetched(:final file) => _Text(file),
          SchemaFetchFailed(:final diagnostic) => _Failed([diagnostic]),
        };
    }
  }

  ProjectReadResult _readSources(CodegenConfig config, ProjectFile schema) {
    final problems = <Diagnostic>[];
    final documents = <ProjectFile>[];
    for (final path in _documentPaths(config, schema.path)) {
      final text = _readText(path);
      switch (text) {
        case _FileText():
          documents.add(ProjectFile(path, text.text));
        case _FileFailed():
          problems.add(text.problem);
      }
    }
    if (problems.isNotEmpty) return ProjectReadFailed(problems);
    return ProjectRead(config, schema, documents);
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

  _FileOutcome _readText(String path) {
    try {
      return _FileText(File(p.join(directory, path)).readAsStringSync());
    } on FileSystemException catch (error) {
      return _FileFailed(
        _unreadable(path, error.osError?.message ?? error.message),
      );
    } on FormatException catch (error) {
      return _FileFailed(_unreadable(path, error.message));
    }
  }

  Diagnostic _unreadable(String path, String reason) => Diagnostic(
    .inputUnreadable,
    .error,
    "Cannot read '$path': $reason.",
  );
}

sealed class _FileOutcome {
  const _FileOutcome();
}

final class _FileText extends _FileOutcome {
  const _FileText(this.text);
  final String text;
}

final class _FileFailed extends _FileOutcome {
  const _FileFailed(this.problem);
  final Diagnostic problem;
}

sealed class _SchemaOutcome {
  const _SchemaOutcome();
}

final class _Text extends _SchemaOutcome {
  const _Text(this.file);
  final ProjectFile file;
}

final class _Failed extends _SchemaOutcome {
  const _Failed(this.problems);
  final List<Diagnostic> problems;
}
