import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_class.dart';
import 'imports.dart';

/// Records the imports of a generated document library (spec §7 "Files").
///
/// {@category codegen}
final class LibraryImports {
  /// Creates the recorder.
  ///
  /// [schemaTypesPath] is the schema-types library and [fragmentLibraries]
  /// the library of each fragment, by fragment name; all paths are relative
  /// to the configuration file.
  const LibraryImports(
    this.schema,
    this.schemaTypesPath,
    this.fragmentLibraries,
  );

  /// The schema the field types belong to.
  final Schema schema;

  /// The path of the schema-types library.
  final String schemaTypesPath;

  /// The library path that defines each fragment, by fragment name.
  final Map<String, String> fragmentLibraries;

  /// Records into [imports] what the library at [libraryPath] needs for
  /// [classes]. The imports of custom scalars are recorded while the classes
  /// are written.
  void record(
    Imports imports,
    String libraryPath,
    List<PlannedClass> classes,
  ) {
    if (classes.isEmpty) {
      return;
    }
    imports.package(
      'package:typed_graphql/typed_graphql.dart',
      prefix: 'graphql',
    );
    imports.package(
      'package:typed_graphql_client/typed_graphql_client.dart',
      prefix: 'client',
    );
    final targets = <String>{
      if (_usesSchemaTypes(classes)) schemaTypesPath,
      for (final fragment in _spreadFragments(classes))
        ?fragmentLibraries[fragment],
    }..remove(libraryPath);
    for (final target in targets) {
      imports.relative(
        p.posix.relative(target, from: p.posix.dirname(libraryPath)),
      );
    }
  }

  bool _usesSchemaTypes(List<PlannedClass> classes) => classes.any(
    (planned) =>
        planned is DataClassPlan &&
        planned.fields.any(
          (field) => switch (schema.namedTypeOf(field.type)) {
            EnumType() || InputObjectType() => true,
            _ => false,
          },
        ),
  );

  Iterable<String> _spreadFragments(List<PlannedClass> classes) => [
    for (final planned in classes)
      if (planned is FragmentHolderPlan)
        for (final fragment in planned.fragments) fragment.fragmentName,
  ];
}
