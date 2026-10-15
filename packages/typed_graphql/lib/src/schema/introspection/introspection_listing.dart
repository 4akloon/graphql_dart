import '../../language/ast/type_ref.dart';
import '../build/built_ins.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';

/// Which types and directives introspection lists for a schema, and in which
/// order (spec §4.2): the schema's own in declaration order, then the
/// built-in scalars it references (`String` and `Boolean` always), then the
/// introspection types; the built-in directives it did not redefine come
/// after its own.
///
/// {@category introspection}
final class IntrospectionListing(
  /// The schema listed.
  final Schema schema,
) {
  /// Lists [schema].
  this;

  /// The types in the order introspection lists them.
  List<SchemaType> get types {
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
      for (final directive in directives)
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

  /// The directives in the order introspection lists them.
  List<SchemaDirective> get directives {
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
}
