import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random operations and fragments for the round-trip fuzzer.
final class RandomExecutable {
  /// Draws from [parts].
  RandomExecutable(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  /// An operation. Only the first definition may take the shorthand
  /// form `{ ... }`: after a definition with an optional body, such as
  /// `type T`, the `{` would read as that body. Only a named operation has
  /// a description, since graphql-js rejects one on an anonymous
  /// operation.
  OperationDefinition operation({required bool isFirst}) {
    final type = parts.pick(OperationType.values);
    final variables = parts.some(2, _variableDefinition);
    final directives = parts.directives(isConst: false);
    final isShorthand =
        type == OperationType.query && variables.isEmpty && directives.isEmpty;
    final isNamed = parts.chance(70) || (isShorthand && !isFirst);
    final name = isNamed ? parts.name() : null;
    return OperationDefinition(
      type,
      selectionSet(),
      description: isNamed ? parts.description() : null,
      name: name,
      variableDefinitions: variables,
      directives: directives,
    );
  }

  /// A fragment definition.
  FragmentDefinition fragment() => FragmentDefinition(
    parts.fragmentName(),
    NamedType(parts.name()),
    selectionSet(),
    description: parts.description(),
    directives: parts.directives(isConst: false),
  );

  /// One to three selections, nested at most three levels.
  SelectionSet selectionSet({int depth = 0}) =>
      SelectionSet(parts.some(3, () => _selection(depth), min: 1));

  Selection _selection(int depth) => switch (parts.random.nextInt(5)) {
    0 => FragmentSpread(
      parts.fragmentName(),
      directives: parts.directives(isConst: false),
    ),
    1 => InlineFragment(
      parts.chance(70) ? NamedType(parts.name()) : null,
      selectionSet(depth: depth + 1),
      directives: parts.directives(isConst: false),
    ),
    _ => _field(depth),
  };

  Field _field(int depth) => Field(
    parts.chance(20) ? parts.name() : null,
    parts.name(),
    arguments: parts.arguments(isConst: false),
    directives: parts.directives(isConst: false),
    selectionSet: depth < 3 && parts.chance(40)
        ? selectionSet(depth: depth + 1)
        : null,
  );

  VariableDefinition _variableDefinition() => VariableDefinition(
    Variable(parts.name()),
    parts.type(),
    description: parts.description(),
    defaultValue: parts.chance(30) ? parts.value(isConst: true) : null,
    directives: parts.directives(isConst: true),
  );
}
