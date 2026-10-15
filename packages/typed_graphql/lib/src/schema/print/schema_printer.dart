import '../../language/ast/operation_type.dart';
import '../build/built_ins.dart';
import '../schema.dart';
import 'member_printer.dart';
import 'type_printer.dart';

/// Prints a schema as SDL, as graphql-js's `printSchema` does (spec §5;
/// R2.5): the schema definition when it says more than the default root
/// names, then the directive definitions and the types, in declaration
/// order, separated by a blank line.
///
/// Unlike graphql-js, every applied directive is printed as written, so
/// SDL to schema to SDL loses nothing but a schema description or
/// directives without root types, which SDL cannot hold.
///
/// {@category schema}
final class const SchemaPrinter({
  /// Whether the built-in directives, scalars and introspection types
  /// are printed too, around the declared ones; `@defer`, `@stream`,
  /// `@cost` and `@listSize` only when the schema includes them.
  final bool includesBuiltIns = false,
}) {
  /// Creates a printer.
  this;

  static const TypePrinter _types = TypePrinter();
  static const BuiltIns _builtIns = BuiltIns();

  /// [schema] as SDL, without a trailing line break.
  String print(Schema schema) {
    return [
      ?_schemaDefinition(schema),
      if (includesBuiltIns)
        ...[
          ..._builtIns.directives,
          if (schema.includesDeferAndStream) ...[
            _builtIns.defer,
            _builtIns.stream,
          ],
          if (schema.includesCostDirectives) ...[
            _builtIns.cost,
            _builtIns.listSize,
          ],
        ].map(_types.directive),
      ...schema.directives.map(_types.directive),
      if (includesBuiltIns) ..._builtIns.scalars.map(_types.type),
      ...schema.types.map(_types.type),
      if (includesBuiltIns) ..._builtIns.introspectionTypes.map(_types.type),
    ].join('\n\n');
  }

  String? _schemaDefinition(Schema schema) {
    final roots = [
      for (final operation in OperationType.values)
        if (schema.rootTypeName(operation) case final name?)
          '  ${operation.name}: $name\n',
    ];
    final isPlain =
        schema.description == null &&
        schema.appliedDirectives.isEmpty &&
        _hasDefaultRoots(schema);
    if (roots.isEmpty || isPlain) {
      return null;
    }
    const members = MemberPrinter();
    return '${members.description(schema.description)}'
        'schema${members.directives(schema.appliedDirectives)} '
        '{\n${roots.join()}}';
  }

  /// Whether each root is the type named after its operation, and each
  /// type named after an operation is its root.
  ///
  /// Stricter than graphql-js's `isSchemaOfCommonNames`: a non-root type
  /// named `Query`, `Mutation` or `Subscription` also forces the schema
  /// definition, so building the printed SDL infers the same roots.
  static bool _hasDefaultRoots(Schema schema) => OperationType.values.every((
    operation,
  ) {
    final defaultName = switch (operation) {
      .query => 'Query',
      .mutation => 'Mutation',
      .subscription => 'Subscription',
    };
    final named = schema.typeNamed(defaultName) == null ? null : defaultName;
    return schema.rootTypeName(operation) == named;
  });
}
