import 'package:typed_graphql/typed_graphql.dart';

import 'schema_mapper.dart';

/// The two views of a random schema the introspection fuzzers compare:
/// [closed] can be introspected, and [carried] is what an introspection
/// result can carry of a schema.
final class IntrospectionView {
  /// Creates the views; they keep no state.
  const IntrospectionView();

  /// The default reason of `@deprecated` (September2025 §3.13.3), which
  /// `fromIntrospection` reads back as `@deprecated` without an argument.
  static const String _defaultReason = 'No longer supported';

  /// [schema] with every reference to a type it lacks replaced: a field or
  /// argument type by `String` (in the same wrappers), an interface or a
  /// union member left out. `toIntrospection` refuses the original.
  Schema closed(Schema schema) => SchemaMapper(
    type: (type) => _KnownTypes(schema).transform(type)! as TypeRef,
    references: (references) => [
      for (final reference in references)
        if (schema.typeNamed(reference.name) != null) reference,
    ],
    directives: _applied,
  ).map(schema);

  /// [schema] with only the directives introspection carries: a scalar's
  /// `@specifiedBy`, an input object's `@oneOf` and the `@deprecated` of a
  /// field, argument, input field or enum value, written as
  /// `fromIntrospection` writes them. Directive deprecation is not in
  /// `IntrospectionQuery.full`.
  Schema carried(Schema schema) => SchemaMapper(
    type: (type) => type,
    references: (references) => references,
    directives: _carriedDirectives,
  ).map(schema);

  List<AppliedDirective> _applied(Object element) => switch (element) {
    Schema(:final appliedDirectives) ||
    SchemaType(:final appliedDirectives) ||
    SchemaField(:final appliedDirectives) ||
    InputValue(:final appliedDirectives) ||
    SchemaEnumValue(:final appliedDirectives) ||
    SchemaDirective(:final appliedDirectives) => appliedDirectives,
    _ => throw ArgumentError.value(element, 'element', 'not an element'),
  };

  List<AppliedDirective> _carriedDirectives(Object element) =>
      switch (element) {
        ScalarType(:final specifiedByUrl?) => [
          _withString('specifiedBy', 'url', specifiedByUrl),
        ],
        InputObjectType(isOneOf: true) => [AppliedDirective('oneOf')],
        SchemaField(:final deprecationReason?) ||
        InputValue(:final deprecationReason?) ||
        SchemaEnumValue(:final deprecationReason?) => [
          if (deprecationReason == _defaultReason)
            AppliedDirective('deprecated')
          else
            _withString('deprecated', 'reason', deprecationReason),
        ],
        _ => const [],
      };

  AppliedDirective _withString(String name, String argument, String text) =>
      AppliedDirective(
        name,
        arguments: [Argument(Name(argument), StringValue(text))],
      );
}

/// Replaces a named type the schema lacks by `String`.
final class _KnownTypes extends AstTransformer {
  _KnownTypes(this.schema);

  final Schema schema;

  @override
  Node? rewrite(Node node) => switch (node) {
    NamedType(:final name) when schema.typeNamed(name.value) == null =>
      const NamedType(Name('String')),
    _ => node,
  };
}
