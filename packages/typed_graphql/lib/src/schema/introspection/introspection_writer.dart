import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import '../build/built_ins.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'introspection_query.dart';
import 'type_writer.dart';

/// Writes a schema as the `data` of its answer to an [IntrospectionQuery]
/// (graphql-js's `introspectionFromSchema`), without executing the query.
///
/// Types are listed in declaration order, then the built-in scalars the
/// schema references (`String` and `Boolean` always, as introspection
/// does; spec §3.5), then the introspection types. Directives are listed
/// in declaration order, then the built-in ones the schema did not
/// redefine.
final class IntrospectionWriter(
  /// The schema written.
  final Schema schema,

  /// The query whose answer is written.
  final IntrospectionQuery query,
) {
  /// Creates a writer.
  this;

  final TypeWriter _types = TypeWriter(schema, query);

  /// `{"__schema": {...}}`.
  ///
  /// A reference to a type the schema lacks is an [ArgumentError]:
  /// introspection describes a schema that validation accepts. A
  /// [IntrospectionQuery.typeDepth] outside 0 to 100 is a [RangeError].
  JsonObject write() {
    query.checkTypeDepth();
    return _schemaObject();
  }

  JsonObject _schemaObject() => JsonObject({
    '__schema': JsonObject({
      if (query.includesSchemaDescription && query.includesDescriptions)
        'description': switch (schema.description) {
          final description? => JsonString(description),
          null => const JsonNull(),
        },
      'queryType': _root(schema.queryTypeName),
      'mutationType': _root(schema.mutationTypeName),
      'subscriptionType': _root(schema.subscriptionTypeName),
      'types': JsonArray([
        for (final type in _listedTypes()) _types.type(type),
      ]),
      'directives': JsonArray([
        for (final directive in _listedDirectives()) _directive(directive),
      ]),
    }),
  });

  JsonValue _root(String? name) => switch (name) {
    final name? => JsonObject({
      'name': JsonString(name),
      'kind': JsonString(_types.references.kindNamed(name)),
    }),
    null => const JsonNull(),
  };

  List<SchemaType> _listedTypes() {
    const builtIns = BuiltIns();
    final referenced = _referencedTypeNames();
    return [
      ...schema.types,
      for (final scalar in builtIns.scalars)
        if (identical(schema.typeNamed(scalar.name), scalar) &&
            referenced.contains(scalar.name))
          scalar,
      for (final type in builtIns.introspectionTypes)
        if (identical(schema.typeNamed(type.name), type)) type,
    ];
  }

  // Only for lookups, never iterated.
  Set<String> _referencedTypeNames() {
    final references = <TypeRef>[
      for (final type in schema.types) ..._typeReferences(type),
      for (final directive in _listedDirectives())
        for (final argument in directive.arguments) argument.type,
    ];
    const comparator = TypeComparator();
    return {
      // The introspection types reference both.
      'String',
      'Boolean',
      for (final reference in references) comparator.namedTypeName(reference),
    };
  }

  List<TypeRef> _typeReferences(SchemaType type) => switch (type) {
    ObjectType(:final fields) || InterfaceType(:final fields) => [
      for (final field in fields) ...[
        field.type,
        ..._inputTypes(field.arguments),
      ],
    ],
    InputObjectType(:final fields) => _inputTypes(fields),
    ScalarType() || UnionType() || EnumType() => const [],
  };

  List<TypeRef> _inputTypes(List<InputValue> values) => [
    for (final value in values) value.type,
  ];

  List<SchemaDirective> _listedDirectives() {
    const builtIns = BuiltIns();
    return [
      ...schema.directives,
      for (final directive in [
        ...builtIns.directives,
        builtIns.defer,
        builtIns.stream,
        builtIns.cost,
        builtIns.listSize,
      ])
        if (identical(schema.directiveNamed(directive.name), directive))
          directive,
    ];
  }

  JsonObject _directive(SchemaDirective directive) => JsonObject({
    'name': JsonString(directive.name),
    if (query.includesDescriptions)
      'description': switch (directive.description) {
        final description? => JsonString(description),
        null => const JsonNull(),
      },
    if (query.includesDirectiveIsRepeatable)
      'isRepeatable': JsonBool(directive.isRepeatable),
    if (query.includesDirectiveDeprecation)
      ..._types.deprecation(directive.deprecationReason),
    'locations': JsonArray([
      for (final location in directive.locations) JsonString(location.spelling),
    ]),
    'args': _types.inputValues(directive.arguments),
  });
}
