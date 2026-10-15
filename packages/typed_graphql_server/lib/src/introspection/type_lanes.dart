import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';
import 'type_kind.dart';

/// The fields of `__Type` over the core schema; the parent is an
/// [IntrospectedType] (September2025 4.2.1).
final class TypeLanes(
  /// The schema whose types are described.
  final Schema schema,
) {
  /// Reads [schema].
  this;

  /// The fields by name.
  Map<String, FieldDef<Object?, Object?>> get fields =>
      IntrospectionFields.table(
        [
          IntrospectionFields.pure<IntrospectedType>('kind', _kind),
          IntrospectionFields.pure<IntrospectedType>(
            'name',
            (type) => _named(type)?.name,
          ),
          IntrospectionFields.pure<IntrospectedType>(
            'description',
            (type) => _named(type)?.description,
          ),
          IntrospectionFields.pure<IntrospectedType>('specifiedByURL', (type) {
            final named = _named(type);
            return named is ScalarType ? named.specifiedByUrl : null;
          }),
          IntrospectionFields.pure<IntrospectedType>('isOneOf', (type) {
            final named = _named(type);
            return named is InputObjectType ? named.isOneOf : null;
          }),
          IntrospectionFields.withArguments<IntrospectedType>(
            'fields',
            _fields,
          ),
          IntrospectionFields.pure<IntrospectedType>('interfaces', _interfaces),
          IntrospectionFields.pure<IntrospectedType>(
            'possibleTypes',
            _possibleTypes,
          ),
          IntrospectionFields.withArguments<IntrospectedType>(
            'enumValues',
            _enumValues,
          ),
          IntrospectionFields.withArguments<IntrospectedType>(
            'inputFields',
            _inputFields,
          ),
          IntrospectionFields.pure<IntrospectedType>('ofType', _ofType),
        ],
      );

  SchemaType? _named(IntrospectedType type) => switch (type.reference) {
    NamedType(:final name) => schema.typeNamed(name.value),
    _ => null,
  };

  TypeKind _kind(IntrospectedType type) => switch (type.reference) {
    ListType() => TypeKind.list,
    NonNullType() => TypeKind.nonNull,
    NamedType(:final name) => switch (schema.typeNamed(name.value)) {
      ScalarType() => TypeKind.scalar,
      ObjectType() => TypeKind.object,
      InterfaceType() => TypeKind.interface,
      UnionType() => TypeKind.union,
      EnumType() => TypeKind.enumeration,
      InputObjectType() => TypeKind.inputObject,
      null => throw StateError('"${name.value}" is not a type of the schema.'),
    },
  };

  List<SchemaField>? _fields(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) {
    final includesDeprecated = IntrospectionFields.includesDeprecated(
      arguments,
    );
    return switch (_named(type)) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields)
          if (includesDeprecated || field.deprecationReason == null) field,
      ],
      _ => null,
    };
  }

  List<IntrospectedType>? _interfaces(IntrospectedType type) =>
      switch (_named(type)) {
        ObjectType(:final interfaces) ||
        InterfaceType(:final interfaces) => _references(interfaces),
        _ => null,
      };

  // Interfaces list their implementers; a union lists every member, as the
  // core writes them.
  List<IntrospectedType>? _possibleTypes(IntrospectedType type) =>
      switch (_named(type)) {
        final InterfaceType named => [
          for (final possible in schema.possibleTypes(named))
            IntrospectedType.named(possible.name),
        ],
        UnionType(:final memberTypes) => _references(memberTypes),
        _ => null,
      };

  List<SchemaEnumValue>? _enumValues(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) {
    final includesDeprecated = IntrospectionFields.includesDeprecated(
      arguments,
    );
    return switch (_named(type)) {
      EnumType(:final values) => [
        for (final value in values)
          if (includesDeprecated || value.deprecationReason == null) value,
      ],
      _ => null,
    };
  }

  List<InputValue>? _inputFields(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) => switch (_named(type)) {
    InputObjectType(:final fields) => [
      for (final field in fields)
        if (IntrospectionFields.includesDeprecated(arguments) ||
            field.deprecationReason == null)
          field,
    ],
    _ => null,
  };

  IntrospectedType? _ofType(IntrospectedType type) => switch (type.reference) {
    ListType(:final type) || NonNullType(:final type) => IntrospectedType(type),
    NamedType() => null,
  };

  List<IntrospectedType> _references(List<NamedTypeReference> references) => [
    for (final reference in references) IntrospectedType.named(reference.name),
  ];
}
