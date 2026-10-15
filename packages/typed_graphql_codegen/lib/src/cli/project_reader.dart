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
    switch (_readText(configName)) {
      case _FileFailed(:final problem):
        return ProjectReadFailed([problem]);
      case _FileText(:final text):
        switch (CodegenConfig.parse(text, path: configName)) {
          case ConfigFailure(:final diagnostics):
            return ProjectReadFailed(diagnostics);
          case ConfigSuccess(:final config):
            return _readProject(config);
        }
    }
  }

  Future<ProjectReadResult> _readProject(CodegenConfig config) async {
    return switch (await _readSchema(config)) {
      _Text(:final file, :final secrets) => _readSources(config, file, secrets),
      _Failed(:final problems, :final secrets) => ProjectReadFailed(
        problems,
        secrets,
      ),
    };
  }

  Future<_SchemaOutcome> _readSchema(CodegenConfig config) async {
    switch (config.schema) {
      case SchemaFile(:final path):
        return switch (_readText(path)) {
          _FileText(:final text) => _Text(ProjectFile(path, text), const []),
          _FileFailed(:final problem) => _Failed([problem], const []),
        };
      case SchemaUrl(:final url):
        final expansion = HeaderExpander(environment).expand(config.headers);
        if (expansion.problems.isNotEmpty) {
          return _Failed(expansion.problems, expansion.secrets);
        }
        final fetched = await fetcher.fetch(
          url,
          expansion.headers,
          secrets: expansion.secrets,
        );
        return switch (fetched) {
          SchemaFetched(:final file) => _Text(file, expansion.secrets),
          SchemaFetchFailed(:final diagnostic) => _Failed(
            [diagnostic],
            expansion.secrets,
          ),
        };
    }
  }

  ProjectReadResult _readSources(
    CodegenConfig config,
    ProjectFile schema,
    List<String> secrets,
  ) {
    final listing = _documentPaths(config, schema.path);
    final problems = [...listing.problems];
    final documents = <ProjectFile>[];
    for (final path in listing.paths) {
      switch (_readText(path)) {
        case _FileText(:final text):
          documents.add(ProjectFile(path, text));
        case _FileFailed(:final problem):
          problems.add(problem);
      }
    }
    if (problems.isNotEmpty) return ProjectReadFailed(problems, secrets);
    return ProjectRead(config, schema, documents, secrets);
  }

  // Symbolic links are not followed: a link to a file outside the project
  // would get around the rule that paths stay inside it.
  ({List<String> paths, List<Diagnostic> problems}) _documentPaths(
    CodegenConfig config,
    String schemaPath,
  ) {
    final paths = <String>{};
    final problems = <Diagnostic>[];
    for (final pattern in config.documents) {
      try {
        final entities = Glob(pattern).listSync(
          root: directory,
          followLinks: false,
        );
        if (!_collect(entities, schemaPath, paths)) {
          problems.add(_leavesProject(pattern));
        }
      } on FormatException catch (error) {
        problems.add(
          Diagnostic(
            .invalidConfig,
            .error,
            "The documents pattern '$pattern' is not valid: ${error.message}.",
          ),
        );
      } on FileSystemException catch (error) {
        problems.add(
          _unreadable(
            pattern,
            error.osError?.message ?? error.message,
          ),
        );
      }
    }
    return (paths: paths.toList()..sort(), problems: problems);
  }

  /// Adds the documents among [entities] to [paths]; false when one lies
  /// outside the project.
  bool _collect(
    List<FileSystemEntity> entities,
    String schemaPath,
    Set<String> paths,
  ) {
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.graphql')) continue;
      final parts = p.split(p.relative(entity.path, from: directory));
      // A brace alternative such as `{..,lib}` passes the path rule, which
      // only checks whole segments.
      if (parts.first == '..') return false;
      final relative = p.posix.joinAll(parts);
      if (relative != schemaPath) paths.add(relative);
    }
    return true;
  }

  Diagnostic _leavesProject(String pattern) => Diagnostic(
    .invalidConfig,
    .error,
    "The documents pattern '$pattern' matches a file outside the project.",
  );

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
  const _Text(this.file, this.secrets);
  final ProjectFile file;
  final List<String> secrets;
}

final class _Failed extends _SchemaOutcome {
  const _Failed(this.problems, this.secrets);
  final List<Diagnostic> problems;
  final List<String> secrets;
}
