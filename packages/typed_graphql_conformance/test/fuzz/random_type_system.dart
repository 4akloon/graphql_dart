import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random type-system definitions and extensions for the round-trip
/// fuzzer, the working draft's directive extensions included.
final class RandomTypeSystem {
  /// Draws from [parts].
  RandomTypeSystem(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  static const List<String> _locations = [
    'QUERY',
    'FIELD',
    'FRAGMENT_SPREAD',
    'VARIABLE_DEFINITION',
    'SCHEMA',
    'OBJECT',
    'ARGUMENT_DEFINITION',
    'ENUM_VALUE',
    'INPUT_FIELD_DEFINITION',
    'DIRECTIVE_DEFINITION',
  ];

  /// A definition of any kind.
  TypeSystemDefinition definition() {
    final name = parts.name();
    final description = parts.description();
    final directives = parts.directives(isConst: true);
    return switch (parts.random.nextInt(8)) {
      0 => SchemaDefinition(
        description: description,
        directives: directives,
        operationTypes: _operationTypes(min: 1),
      ),
      1 => ScalarTypeDefinition(
        name,
        description: description,
        directives: directives,
      ),
      2 => ObjectTypeDefinition(
        name,
        description: description,
        interfaces: _namedTypes(),
        directives: directives,
        fields: parts.some(3, _field),
      ),
      3 => InterfaceTypeDefinition(
        name,
        description: description,
        interfaces: _namedTypes(),
        directives: directives,
        fields: parts.some(3, _field),
      ),
      4 => UnionTypeDefinition(
        name,
        description: description,
        directives: directives,
        types: _namedTypes(),
      ),
      5 => EnumTypeDefinition(
        name,
        description: description,
        directives: directives,
        values: parts.some(3, _enumValue),
      ),
      6 => InputObjectTypeDefinition(
        name,
        description: description,
        directives: directives,
        fields: parts.some(3, _inputValue),
      ),
      _ => DirectiveDefinition(
        name,
        description: description,
        arguments: parts.some(2, _inputValue),
        directives: directives,
        isRepeatable: parts.random.nextBool(),
        locations: parts.some(3, () => Name(parts.pick(_locations)), min: 1),
      ),
    };
  }

  /// An extension of any kind; each has at least one part, as the
  /// grammar requires.
  TypeSystemExtension extension() {
    final name = parts.name();
    final directives = parts.directives(isConst: true);
    final minimum = directives.isEmpty ? 1 : 0;
    return switch (parts.random.nextInt(8)) {
      0 => SchemaExtension(
        directives: directives,
        operationTypes: _operationTypes(min: minimum),
      ),
      1 => ScalarTypeExtension(name, directives: _atLeastOne(directives)),
      2 => ObjectTypeExtension(
        name,
        directives: directives,
        fields: parts.some(3, _field, min: minimum),
      ),
      3 => InterfaceTypeExtension(
        name,
        interfaces: _namedTypes(min: minimum),
        directives: directives,
      ),
      4 => UnionTypeExtension(
        name,
        directives: directives,
        types: _namedTypes(min: minimum),
      ),
      5 => EnumTypeExtension(
        name,
        directives: directives,
        values: parts.some(3, _enumValue, min: minimum),
      ),
      6 => InputObjectTypeExtension(
        name,
        directives: directives,
        fields: parts.some(3, _inputValue, min: minimum),
      ),
      _ => DirectiveExtension(name, directives: _atLeastOne(directives)),
    };
  }

  List<Directive> _atLeastOne(List<Directive> directives) =>
      directives.isEmpty ? [Directive(parts.name())] : directives;

  List<OperationTypeDefinition> _operationTypes({required int min}) =>
      parts.some(
        3,
        () => OperationTypeDefinition(
          parts.pick(OperationType.values),
          NamedType(parts.name()),
        ),
        min: min,
      );

  List<NamedType> _namedTypes({int min = 0}) =>
      parts.some(3, () => NamedType(parts.name()), min: min);

  FieldDefinition _field() => FieldDefinition(
    parts.name(),
    parts.type(),
    description: parts.description(),
    arguments: parts.some(2, _inputValue),
    directives: parts.directives(isConst: true),
  );

  InputValueDefinition _inputValue() => InputValueDefinition(
    parts.name(),
    parts.type(),
    description: parts.description(),
    defaultValue: parts.chance(30) ? parts.value(isConst: true) : null,
    directives: parts.directives(isConst: true),
  );

  EnumValueDefinition _enumValue() => EnumValueDefinition(
    parts.enumValueName(),
    description: parts.description(),
    directives: parts.directives(isConst: true),
  );
}
