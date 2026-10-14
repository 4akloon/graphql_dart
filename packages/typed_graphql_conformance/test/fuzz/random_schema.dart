import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random schemas for the SDL round-trip fuzzer: every kind of type and
/// element, with names that are unique where the builder requires it and
/// never a built-in's, so the printed text builds without diagnostics.
final class RandomSchema {
  /// Draws from [parts].
  RandomSchema(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  static const List<String> _locations = [
    'QUERY',
    'FIELD',
    'FRAGMENT_SPREAD',
    'SCHEMA',
    'SCALAR',
    'OBJECT',
    'FIELD_DEFINITION',
    'ARGUMENT_DEFINITION',
    'ENUM_VALUE',
    'INPUT_OBJECT',
  ];

  /// A schema of up to six types and two directive definitions. A type
  /// named `Query` is always the query root: SDL without a schema
  /// definition makes it one.
  Schema schema() {
    final types = _members(6, _type);
    final objects = [
      for (final type in types)
        if (type is ObjectType) type.name,
    ];
    final hasQuery = objects.isNotEmpty && parts.chance(80);
    final query = hasQuery && parts.chance(30) ? 'Query' : null;
    final roots = (
      query: hasQuery ? (query ?? parts.pick(objects)) : null,
      mutation: objects.isNotEmpty && parts.chance(30)
          ? parts.pick(objects)
          : null,
    );
    final hasRoots = roots.query != null || roots.mutation != null;
    return Schema(
      types: [
        if (query != null) ObjectType(query, fields: _members(2, _field)),
        ...types,
      ],
      directives: _members(2, _directive),
      queryTypeName: roots.query,
      mutationTypeName: roots.mutation,
      description: hasRoots ? _description() : null,
      appliedDirectives: hasRoots ? _applied() : const [],
    );
  }

  SchemaType _type(String name) {
    final description = _description();
    final applied = _applied();
    return switch (parts.random.nextInt(6)) {
      0 => ScalarType(
        name,
        description: description,
        appliedDirectives: applied,
      ),
      1 => ObjectType(
        name,
        description: description,
        interfaces: parts.some(2, () => NamedType(parts.name())),
        appliedDirectives: applied,
        fields: _members(3, _field),
      ),
      2 => InterfaceType(
        name,
        description: description,
        interfaces: parts.some(2, () => NamedType(parts.name())),
        appliedDirectives: applied,
        fields: _members(3, _field),
      ),
      3 => UnionType(
        name,
        description: description,
        appliedDirectives: applied,
        memberTypes: parts.some(3, () => NamedType(parts.name())),
      ),
      4 => EnumType(
        name,
        description: description,
        appliedDirectives: applied,
        values: _members(
          3,
          (name) => SchemaEnumValue(
            name,
            description: _description(),
            appliedDirectives: _applied(),
          ),
        ),
      ),
      _ => InputObjectType(
        name,
        description: description,
        appliedDirectives: applied,
        fields: _members(3, _inputValue),
      ),
    };
  }

  SchemaDirective _directive(String name) => SchemaDirective(
    name,
    description: _description(),
    arguments: _members(2, _inputValue),
    isRepeatable: parts.random.nextBool(),
    locations: parts.some(3, () => parts.pick(_locations), min: 1),
    appliedDirectives: _applied(),
  );

  SchemaField _field(String name) => SchemaField(
    name,
    parts.type(),
    description: _description(),
    arguments: _members(2, _inputValue),
    appliedDirectives: _applied(),
  );

  InputValue _inputValue(String name) => InputValue(
    name,
    parts.type(),
    description: _description(),
    defaultValue: parts.chance(40) ? parts.value(isConst: true) : null,
    appliedDirectives: _applied(),
  );

  /// Up to [max] members made by [make], each with its own name.
  List<T> _members<T>(int max, T Function(String name) make) => List.generate(
    parts.random.nextInt(max + 1),
    (index) => make(_unique(index)),
  );

  /// A random name made unique by [index]; no built-in name ends in `_`
  /// and a digit, and neither does `Query`.
  String _unique(int index) => '${parts.enumValueName().value}_$index';

  String? _description() => parts.description()?.value;

  List<AppliedDirective> _applied() => [
    for (final directive in parts.directives(isConst: true))
      AppliedDirective(directive.name.value, arguments: directive.arguments),
  ];
}
