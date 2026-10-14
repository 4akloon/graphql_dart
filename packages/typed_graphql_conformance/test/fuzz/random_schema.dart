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

  /// The 19 directive locations of the September2025 edition.
  static final List<DirectiveLocation> _locations = [
    for (final location in DirectiveLocation.values)
      if (location != .directiveDefinition) location,
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
      subscription: objects.isNotEmpty && parts.chance(30)
          ? parts.pick(objects)
          : null,
    );
    final hasRoots =
        roots.query != null ||
        roots.mutation != null ||
        roots.subscription != null;
    return Schema(
      types: [
        if (query != null) ObjectType(query, fields: _members(2, _field)),
        ...types,
      ],
      directives: _members(2, _directive),
      queryTypeName: roots.query,
      mutationTypeName: roots.mutation,
      subscriptionTypeName: roots.subscription,
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
        appliedDirectives: [
          if (parts.chance(40)) _specifiedBy(name),
          ...applied,
        ],
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
            appliedDirectives: _applied(isMaybeDeprecated: true),
          ),
        ),
      ),
      _ => InputObjectType(
        name,
        description: description,
        appliedDirectives: [
          if (parts.chance(30)) AppliedDirective('oneOf'),
          ...applied,
        ],
        fields: _members(3, _inputValue),
      ),
    };
  }

  SchemaDirective _directive(String name) => SchemaDirective(
    name,
    description: _description(),
    arguments: _members(2, _inputValue),
    isRepeatable: parts.random.nextBool(),
    locations: (_locations.toList()..shuffle(parts.random)).sublist(
      0,
      1 + parts.random.nextInt(3),
    ),
    appliedDirectives: _applied(),
  );

  SchemaField _field(String name) => SchemaField(
    name,
    parts.type(),
    description: _description(),
    arguments: _members(2, _inputValue),
    appliedDirectives: _applied(isMaybeDeprecated: true),
  );

  InputValue _inputValue(String name) => InputValue(
    name,
    parts.type(),
    description: _description(),
    defaultValue: parts.chance(40) ? parts.value(isConst: true) : null,
    appliedDirectives: _applied(isMaybeDeprecated: true),
  );

  /// Up to [max] members made by [make], each with its own name.
  List<T> _members<T>(int max, T Function(String name) make) => List.generate(
    parts.random.nextInt(max + 1),
    (index) => make(_unique(index)),
  );

  /// A random name made unique by [index]; no built-in name ends in `_`
  /// and a digit, and neither does `Query`. A `__` prefix is reserved for
  /// introspection, so it is avoided.
  String _unique(int index) {
    final name = parts.enumValueName().value;
    return '${name.startsWith('__') ? 'x$name' : name}_$index';
  }

  String? _description() => parts.description()?.value;

  AppliedDirective _specifiedBy(String name) => AppliedDirective(
    'specifiedBy',
    arguments: [
      Argument(const Name('url'), StringValue('https://example.com/$name')),
    ],
  );

  AppliedDirective _deprecated() => AppliedDirective(
    'deprecated',
    arguments: [
      if (parts.chance(70)) Argument(const Name('reason'), parts.string()),
    ],
  );

  /// Random directives; `@deprecated` first when [isMaybeDeprecated] and
  /// chance says so.
  List<AppliedDirective> _applied({bool isMaybeDeprecated = false}) => [
    if (isMaybeDeprecated && parts.chance(25)) _deprecated(),
    for (final directive in parts.directives(isConst: true))
      AppliedDirective(directive.name.value, arguments: directive.arguments),
  ];
}
