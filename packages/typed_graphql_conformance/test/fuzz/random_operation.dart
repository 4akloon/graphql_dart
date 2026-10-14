import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// Random operations that are valid against a schema by construction
/// (R3.1, R10.4).
///
/// Every field comes from its parent type, has a sub-selection exactly when
/// its type is composite, and gets a valid literal or a variable of the
/// argument's type for each required argument. A response name is used
/// once in the whole document, unless a field is picked again, which then
/// gets a unique alias, so no two fields can conflict. A fragment is
/// created where it is first spread and may be spread again after it is
/// complete, so the spreads never form a cycle.
final class RandomOperation {
  /// Draws from [random] over the types of [schema].
  RandomOperation(this.schema, this.random);

  /// The schema the operation is valid against.
  final Schema schema;

  /// The random source.
  final Random random;

  static const int _maxDepth = 3;

  final Set<String> _usedNames = {};
  final Map<String, VariableDefinition> _variablesByType = {};
  final List<VariableDefinition> _variables = [];
  final List<FragmentDefinition> _fragments = [];
  int _counter = 0;

  /// One query and the fragments it uses.
  Document document() {
    final root = schema.typeNamed(schema.rootTypeName(.query) ?? 'Query');
    if (root is! ObjectType) {
      throw StateError('the schema has no query root');
    }
    final selectionSet = _selectionSet(root, 0);
    return Document([
      OperationDefinition(
        .query,
        selectionSet,
        name: random.nextBool() ? const Name('Generated') : null,
        variableDefinitions: _variables,
      ),
      ..._fragments,
    ]);
  }

  SelectionSet _selectionSet(SchemaType parent, int depth) => SelectionSet([
    for (var i = 0, n = 1 + random.nextInt(3); i < n; i++)
      _selection(parent, depth),
  ]);

  Selection _selection(SchemaType parent, int depth) {
    final kind = random.nextInt(10);
    if (depth >= _maxDepth) {
      return _typename();
    }
    if (parent is UnionType) {
      return kind < 3
          ? _typename()
          : kind < 7
          ? _inlineFragment(parent, depth)
          : _fragmentSpread(parent, depth);
    }
    return switch (kind) {
      < 6 => _field(parent, depth),
      6 => _typename(),
      7 => _inlineFragment(parent, depth),
      _ => _fragmentSpread(parent, depth),
    };
  }

  Field _typename() => Field(null, const Name('__typename'));

  Selection _field(SchemaType parent, int depth) {
    final candidates = switch (parent) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields)
          if (depth < _maxDepth || _isLeaf(field.type)) field,
      ],
      _ => const <SchemaField>[],
    };
    if (candidates.isEmpty) {
      return _typename();
    }
    final field = candidates[random.nextInt(candidates.length)];
    final alias = !_usedNames.add(field.name) || random.nextInt(7) == 0
        ? Name('a${_counter++}')
        : null;
    final target = _named(field.type);
    return Field(
      alias,
      Name(field.name),
      arguments: _arguments(field.arguments),
      directives: _directives(),
      selectionSet: target.isCompositeType
          ? _selectionSet(target, depth + 1)
          : null,
    );
  }

  bool _isLeaf(TypeRef type) => _named(type).isLeafType;

  SchemaType _named(TypeRef type) =>
      schema.namedTypeOf(type) ?? (throw StateError('unknown type $type'));

  InlineFragment _inlineFragment(SchemaType parent, int depth) {
    if (random.nextInt(6) == 0) {
      return InlineFragment(
        null,
        _selectionSet(parent, depth + 1),
        directives: _directives(),
      );
    }
    final type = _overlapping(parent);
    return InlineFragment(
      NamedType(Name(type.name)),
      _selectionSet(type, depth + 1),
      directives: _directives(),
    );
  }

  /// A composite type that shares a possible object type with [parent];
  /// [parent] itself is always one.
  SchemaType _overlapping(SchemaType parent) {
    final candidates = [
      parent,
      for (final type in schema.types)
        if (type.isCompositeType && schema.typesOverlap(parent, type)) type,
    ];
    return candidates[random.nextInt(candidates.length)];
  }

  FragmentSpread _fragmentSpread(SchemaType parent, int depth) {
    final reusable = [
      for (final fragment in _fragments)
        if (schema.typesOverlap(
          parent,
          _named(fragment.typeCondition),
        ))
          fragment,
    ];
    if (reusable.isNotEmpty && random.nextBool()) {
      final fragment = reusable[random.nextInt(reusable.length)];
      return FragmentSpread(fragment.name, directives: _directives());
    }
    final type = _overlapping(parent);
    final name = Name('Frag${_counter++}');
    _fragments.add(
      FragmentDefinition(
        name,
        NamedType(Name(type.name)),
        _selectionSet(type, depth + 1),
      ),
    );
    return FragmentSpread(name, directives: _directives());
  }

  /// `@skip` or `@include`, on a few selections.
  List<Directive> _directives() {
    if (random.nextInt(8) != 0) {
      return const [];
    }
    final condition = random.nextBool()
        ? BooleanValue(random.nextBool())
        : _variableOf(const NonNullType(NamedType(Name('Boolean'))));
    return [
      Directive(
        Name(random.nextBool() ? 'skip' : 'include'),
        arguments: [Argument(const Name('if'), condition)],
      ),
    ];
  }

  List<Argument> _arguments(List<InputValue> declared) => [
    for (final argument in declared)
      if (_isRequired(argument) || random.nextInt(5) < 2)
        Argument(Name(argument.name), _value(argument.type)),
  ];

  bool _isRequired(InputValue value) =>
      value.type is NonNullType && value.defaultValue == null;

  /// A value valid for [type]: a literal, or a variable of [type] (a
  /// non-null one when [isNullable] is false, which a `@oneOf` field and
  /// the inside of a non-null type need).
  Value _value(
    TypeRef type, {
    bool isNullable = true,
    bool allowsVariables = true,
  }) {
    if (allowsVariables && random.nextInt(5) == 0) {
      return _variableOf(isNullable ? type : _nonNull(type));
    }
    return switch (type) {
      NonNullType(:final type) => _value(
        type,
        isNullable: false,
        allowsVariables: allowsVariables,
      ),
      _ when isNullable && random.nextInt(12) == 0 => const NullValue(),
      ListType(:final type) => ListValue([
        for (var i = 0, n = random.nextInt(3); i < n; i++)
          _value(type, allowsVariables: allowsVariables),
      ]),
      NamedType() => _namedValue(
        _named(type),
        allowsVariables: allowsVariables,
      ),
    };
  }

  TypeRef _nonNull(TypeRef type) =>
      type is NonNullType ? type : NonNullType(type);

  Value _namedValue(SchemaType type, {required bool allowsVariables}) =>
      switch (type) {
        EnumType(:final values) => EnumValue(
          values[random.nextInt(values.length)].name,
        ),
        InputObjectType() => _objectValue(
          type,
          allowsVariables: allowsVariables,
        ),
        ScalarType(:final name) => switch (name) {
          'Int' => IntValue('${random.nextInt(100)}'),
          'Float' => FloatValue('${random.nextInt(100)}.5'),
          'Boolean' => BooleanValue(random.nextBool()),
          _ => const StringValue('text'),
        },
        _ => throw StateError('${type.name} is not an input type'),
      };

  ObjectValue _objectValue(
    InputObjectType type, {
    required bool allowsVariables,
  }) {
    if (type.isOneOf) {
      final field = type.fields[random.nextInt(type.fields.length)];
      return ObjectValue([
        ObjectField(
          Name(field.name),
          _value(
            field.type,
            isNullable: false,
            allowsVariables: allowsVariables,
          ),
        ),
      ]);
    }
    return ObjectValue([
      for (final field in type.fields)
        if (_isRequired(field) || random.nextBool())
          ObjectField(
            Name(field.name),
            _value(field.type, allowsVariables: allowsVariables),
          ),
    ]);
  }

  /// A variable of exactly [type], defined for the operation, with a
  /// default value at times.
  Variable _variableOf(TypeRef type) {
    final key = const Printer().print(type);
    final existing = _variablesByType[key];
    if (existing != null) {
      return existing.variable;
    }
    final variable = Variable(Name('v${_counter++}'));
    final definition = VariableDefinition(
      variable,
      type,
      defaultValue: random.nextInt(3) == 0
          ? _value(type, allowsVariables: false)
          : null,
    );
    _variablesByType[key] = definition;
    _variables.add(definition);
    return variable;
  }
}
