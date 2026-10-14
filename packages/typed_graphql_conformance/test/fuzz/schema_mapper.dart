import 'package:typed_graphql/typed_graphql.dart';

/// Rebuilds a schema element by element, changing its type references,
/// its interface and member references and its applied directives, for
/// the introspection fuzzers.
///
/// [directives] gets each element (a [Schema], [SchemaType],
/// [SchemaField], [InputValue], [SchemaEnumValue] or [SchemaDirective])
/// and returns the directives its copy keeps.
final class SchemaMapper {
  /// A mapper that changes what the three functions say.
  const SchemaMapper({
    required this.type,
    required this.references,
    required this.directives,
  });

  /// The type reference a copy holds instead of the given one.
  final TypeRef Function(TypeRef type) type;

  /// The interfaces or union members a copy keeps.
  final List<NamedTypeReference> Function(List<NamedTypeReference> references)
  references;

  /// The directives the copy of an element keeps.
  final List<AppliedDirective> Function(Object element) directives;

  /// The copy of [schema].
  Schema map(Schema schema) => Schema(
    types: [for (final type in schema.types) _type(type)],
    directives: [
      for (final directive in schema.directives)
        SchemaDirective(
          directive.name,
          description: directive.description,
          arguments: _inputValues(directive.arguments),
          isRepeatable: directive.isRepeatable,
          locations: directive.locations,
          appliedDirectives: directives(directive),
        ),
    ],
    queryTypeName: schema.queryTypeName,
    mutationTypeName: schema.mutationTypeName,
    subscriptionTypeName: schema.subscriptionTypeName,
    description: schema.description,
    appliedDirectives: directives(schema),
    includesDeferAndStream: schema.includesDeferAndStream,
  );

  SchemaType _type(SchemaType type) => switch (type) {
    ScalarType(:final name, :final description) => ScalarType(
      name,
      description: description,
      appliedDirectives: directives(type),
    ),
    ObjectType(:final name, :final description) => ObjectType(
      name,
      description: description,
      interfaces: references(type.interfaces),
      appliedDirectives: directives(type),
      fields: _fields(type.fields),
    ),
    InterfaceType(:final name, :final description) => InterfaceType(
      name,
      description: description,
      interfaces: references(type.interfaces),
      appliedDirectives: directives(type),
      fields: _fields(type.fields),
    ),
    UnionType(:final name, :final description) => UnionType(
      name,
      description: description,
      appliedDirectives: directives(type),
      memberTypes: references(type.memberTypes),
    ),
    EnumType(:final name, :final description) => EnumType(
      name,
      description: description,
      appliedDirectives: directives(type),
      values: [
        for (final value in type.values)
          SchemaEnumValue(
            value.name,
            description: value.description,
            appliedDirectives: directives(value),
          ),
      ],
    ),
    InputObjectType(:final name, :final description) => InputObjectType(
      name,
      description: description,
      appliedDirectives: directives(type),
      fields: _inputValues(type.fields),
    ),
  };

  List<SchemaField> _fields(List<SchemaField> fields) => [
    for (final field in fields)
      SchemaField(
        field.name,
        type(field.type),
        description: field.description,
        arguments: _inputValues(field.arguments),
        appliedDirectives: directives(field),
      ),
  ];

  List<InputValue> _inputValues(List<InputValue> values) => [
    for (final value in values)
      InputValue(
        value.name,
        type(value.type),
        description: value.description,
        defaultValue: value.defaultValue,
        appliedDirectives: directives(value),
      ),
  ];
}
