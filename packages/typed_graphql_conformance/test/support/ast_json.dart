import 'package:typed_graphql/typed_graphql.dart';

/// A node as graphql-js's `toJSONDeep` shows it, so a ported AST
/// expectation is copied unchanged: `kind` is graphql-js's `Kind`, `loc` is
/// `{start, end}`, every field graphql-js sets is present, and an absent
/// child or an absent optional list is `null` (graphql-js's `undefined`).
final class AstJson {
  /// Creates the converter; it keeps no state.
  const AstJson();

  /// [node] as graphql-js JSON; `null` for no node.
  Object? of(Node? node) => switch (node) {
    null => null,
    Name(:final value) => _node(node, 'Name', {'value': value}),
    Document(:final definitions) => _node(node, 'Document', {
      'definitions': _all(definitions),
    }),
    Value() => _value(node),
    TypeRef() => _type(node),
    Argument(:final name, :final value) ||
    ObjectField(:final name, :final value) => _node(
      node,
      node is Argument ? 'Argument' : 'ObjectField',
      {
        'name': of(name),
        'value': of(value),
      },
    ),
    Directive(:final name, :final arguments) => _node(node, 'Directive', {
      'name': of(name),
      'arguments': _optional(arguments),
    }),
    ExecutableDefinition() ||
    SelectionSet() ||
    Selection() ||
    VariableDefinition() => _executable(node),
    TypeSystemExtension() => _extension(node),
    _ => _typeSystem(node),
  };

  Map<String, Object?> _node(
    Node node,
    String kind,
    Map<String, Object?> fields,
  ) => {
    'kind': kind,
    'loc': {'start': node.start, 'end': node.end},
    ...fields,
  };

  /// A list graphql-js always sets, such as `ListValue.values`.
  List<Object?> _all(List<Node> nodes) => [for (final node in nodes) of(node)];

  /// A list graphql-js leaves `undefined` when absent, such as `arguments`.
  List<Object?>? _optional(List<Node> nodes) =>
      nodes.isEmpty ? null : _all(nodes);

  Map<String, Object?> _value(Value value) => switch (value) {
    Variable(:final name) => _node(value, 'Variable', {'name': of(name)}),
    IntValue(value: final lexeme) => _node(value, 'IntValue', {
      'value': lexeme,
    }),
    FloatValue(value: final lexeme) => _node(value, 'FloatValue', {
      'value': lexeme,
    }),
    StringValue(value: final text, :final isBlock) => _node(
      value,
      'StringValue',
      {'value': text, 'block': isBlock},
    ),
    BooleanValue(value: final flag) => _node(value, 'BooleanValue', {
      'value': flag,
    }),
    NullValue() => _node(value, 'NullValue', {}),
    EnumValue(value: final name) => _node(value, 'EnumValue', {
      'value': name,
    }),
    ListValue(:final values) => _node(value, 'ListValue', {
      'values': _all(values),
    }),
    ObjectValue(:final fields) => _node(value, 'ObjectValue', {
      'fields': _all(fields),
    }),
  };

  Map<String, Object?> _type(TypeRef type) => switch (type) {
    NamedType(:final name) => _node(type, 'NamedType', {'name': of(name)}),
    ListType(type: final item) => _node(type, 'ListType', {'type': of(item)}),
    NonNullType(type: final item) => _node(type, 'NonNullType', {
      'type': of(item),
    }),
  };

  Map<String, Object?> _executable(Node node) => switch (node) {
    OperationDefinition() => _node(node, 'OperationDefinition', {
      'description': of(node.description),
      'operation': node.operation.name,
      'name': of(node.name),
      'variableDefinitions': _optional(node.variableDefinitions),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    FragmentDefinition() => _node(node, 'FragmentDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'typeCondition': of(node.typeCondition),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    VariableDefinition() => _node(node, 'VariableDefinition', {
      'description': of(node.description),
      'variable': of(node.variable),
      'type': of(node.type),
      'defaultValue': of(node.defaultValue),
      'directives': _optional(node.directives),
    }),
    SelectionSet(:final selections) => _node(node, 'SelectionSet', {
      'selections': _all(selections),
    }),
    Field() => _node(node, 'Field', {
      'alias': of(node.alias),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    FragmentSpread(:final name, :final directives) => _node(
      node,
      'FragmentSpread',
      {'name': of(name), 'directives': _optional(directives)},
    ),
    InlineFragment() => _node(node, 'InlineFragment', {
      'typeCondition': of(node.typeCondition),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    _ => throw ArgumentError.value(node, 'node', 'is not executable'),
  };

  Map<String, Object?> _typeSystem(Node node) => switch (node) {
    SchemaDefinition() => _node(node, 'SchemaDefinition', {
      'description': of(node.description),
      'directives': _optional(node.directives),
      'operationTypes': _all(node.operationTypes),
    }),
    OperationTypeDefinition(:final operation, :final type) => _node(
      node,
      'OperationTypeDefinition',
      {'operation': operation.name, 'type': of(type)},
    ),
    DirectiveDefinition() => _node(node, 'DirectiveDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'directives': _optional(node.directives),
      'repeatable': node.isRepeatable,
      'locations': _all(node.locations),
    }),
    TypeDefinition() => _typeDefinition(node),
    FieldDefinition() => _node(node, 'FieldDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'type': of(node.type),
      'directives': _optional(node.directives),
    }),
    InputValueDefinition() => _node(node, 'InputValueDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'type': of(node.type),
      'defaultValue': of(node.defaultValue),
      'directives': _optional(node.directives),
    }),
    EnumValueDefinition() => _node(node, 'EnumValueDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'directives': _optional(node.directives),
    }),
    _ => throw ArgumentError.value(node, 'node', 'is not a GraphQL node'),
  };

  Map<String, Object?> _typeDefinition(TypeDefinition type) => _node(
    type,
    switch (type) {
      ScalarTypeDefinition() => 'ScalarTypeDefinition',
      ObjectTypeDefinition() => 'ObjectTypeDefinition',
      InterfaceTypeDefinition() => 'InterfaceTypeDefinition',
      UnionTypeDefinition() => 'UnionTypeDefinition',
      EnumTypeDefinition() => 'EnumTypeDefinition',
      InputObjectTypeDefinition() => 'InputObjectTypeDefinition',
    },
    {
      'description': of(type.description),
      'name': of(type.name),
      ..._typeParts(type),
    },
  );

  Map<String, Object?> _extension(TypeSystemExtension extension) => _node(
    extension,
    switch (extension) {
      SchemaExtension() => 'SchemaExtension',
      DirectiveExtension() => 'DirectiveExtension',
      ScalarTypeExtension() => 'ScalarTypeExtension',
      ObjectTypeExtension() => 'ObjectTypeExtension',
      InterfaceTypeExtension() => 'InterfaceTypeExtension',
      UnionTypeExtension() => 'UnionTypeExtension',
      EnumTypeExtension() => 'EnumTypeExtension',
      InputObjectTypeExtension() => 'InputObjectTypeExtension',
    },
    switch (extension) {
      SchemaExtension(:final directives, :final operationTypes) => {
        'directives': _optional(directives),
        'operationTypes': _optional(operationTypes),
      },
      DirectiveExtension(:final name) || TypeExtension(:final name) => {
        'name': of(name),
        ..._typeParts(extension),
      },
    },
  );

  /// The fields after the name, in graphql-js's order.
  Map<String, Object?> _typeParts(Node type) => switch (type) {
    ObjectTypeDefinition(:final interfaces, :final directives, :final fields) ||
    InterfaceTypeDefinition(
      :final interfaces,
      :final directives,
      :final fields,
    ) ||
    ObjectTypeExtension(:final interfaces, :final directives, :final fields) ||
    InterfaceTypeExtension(
      :final interfaces,
      :final directives,
      :final fields,
    ) => {
      'interfaces': _optional(interfaces),
      'directives': _optional(directives),
      'fields': _optional(fields),
    },
    UnionTypeDefinition(:final directives, :final types) ||
    UnionTypeExtension(:final directives, :final types) => {
      'directives': _optional(directives),
      'types': _optional(types),
    },
    EnumTypeDefinition(:final directives, :final values) ||
    EnumTypeExtension(:final directives, :final values) => {
      'directives': _optional(directives),
      'values': _optional(values),
    },
    InputObjectTypeDefinition(:final directives, :final fields) ||
    InputObjectTypeExtension(:final directives, :final fields) => {
      'directives': _optional(directives),
      'fields': _optional(fields),
    },
    ScalarTypeDefinition(:final directives) ||
    ScalarTypeExtension(:final directives) ||
    DirectiveExtension(:final directives) => {
      'directives': _optional(directives),
    },
    _ => throw ArgumentError.value(type, 'type', 'has no type parts'),
  };
}
