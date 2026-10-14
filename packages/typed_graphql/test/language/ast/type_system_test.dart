import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const description = StringValue('Docs.', isBlock: true);
  const node = NamedType(Name('Node'));
  final key = Directive(const Name('key'));
  final field = FieldDefinition(
    const Name('id'),
    const NonNullType(NamedType(Name('ID'))),
    description: description,
    arguments: [
      InputValueDefinition(
        const Name('first'),
        const NamedType(Name('Int')),
        defaultValue: const IntValue('10'),
        directives: [key],
      ),
    ],
    directives: [key],
  );
  final input = InputValueDefinition(
    const Name('limit'),
    const NamedType(Name('Int')),
    description: description,
  );
  final value = EnumValueDefinition(
    const Name('RED'),
    description: description,
    directives: [key],
  );
  const root = OperationTypeDefinition(.query, NamedType(Name('Query')));

  DirectiveDefinition directive({bool isRepeatable = false}) =>
      DirectiveDefinition(
        const Name('key'),
        description: description,
        arguments: [input],
        directives: [key],
        isRepeatable: isRepeatable,
        locations: const [Name('FIELD'), Name('OBJECT')],
        start: 3,
        end: 50,
      );

  final definitions = <TypeSystemDefinition>[
    SchemaDefinition(
      description: description,
      directives: [key],
      operationTypes: const [root],
    ),
    directive(),
    ScalarTypeDefinition(const Name('Date'), description: description),
    ObjectTypeDefinition(
      const Name('User'),
      description: description,
      interfaces: const [node],
      directives: [key],
      fields: [field],
    ),
    InterfaceTypeDefinition(
      const Name('Node'),
      interfaces: const [node],
      fields: [field],
    ),
    UnionTypeDefinition(const Name('U'), types: const [node, node]),
    EnumTypeDefinition(const Name('Color'), values: [value]),
    InputObjectTypeDefinition(const Name('Page'), fields: [input]),
  ];

  final extensions = <TypeSystemExtension>[
    SchemaExtension(directives: [key], operationTypes: const [root]),
    DirectiveExtension(const Name('key'), directives: [key]),
    ScalarTypeExtension(const Name('Date'), directives: [key]),
    ObjectTypeExtension(
      const Name('User'),
      interfaces: const [node],
      directives: [key],
      fields: [field],
    ),
    InterfaceTypeExtension(const Name('Node'), fields: [field]),
    UnionTypeExtension(const Name('U'), types: const [node]),
    EnumTypeExtension(const Name('Color'), values: [value]),
    InputObjectTypeExtension(const Name('Page'), fields: [input]),
  ];

  test('withChildren rebuilds every type system definition', () {
    definitions.forEach(check.expectRebuilds);
  });

  test('withChildren rebuilds every type system extension', () {
    extensions.forEach(check.expectRebuilds);
  });

  test('withChildren rebuilds field, argument and enum value definitions', () {
    <Node>[field, input, value, root].forEach(check.expectRebuilds);
  });

  test('an object type lists interfaces before directives and fields', () {
    expect(definitions[3].children, [
      same(description),
      isA<Name>(),
      same(node),
      same(key),
      same(field),
    ]);
  });

  test('a directive definition lists its locations last', () {
    expect(directive().children, [
      same(description),
      isA<Name>(),
      same(input),
      same(key),
      isA<Name>().having((name) => name.value, 'value', 'FIELD'),
      isA<Name>().having((name) => name.value, 'value', 'OBJECT'),
    ]);
  });

  test('isEquivalentTo compares whether a directive is repeatable', () {
    expect(directive().isEquivalentTo(directive()), isTrue);
    expect(directive().isEquivalentTo(directive(isRepeatable: true)), isFalse);
  });

  test('isEquivalentTo compares the operation of a root type', () {
    expect(
      root.isEquivalentTo(
        const OperationTypeDefinition(.mutation, NamedType(Name('Query'))),
      ),
      isFalse,
    );
  });

  test('a switch over a type definition needs no wildcard', () {
    String keyword(TypeDefinition type) => switch (type) {
      ScalarTypeDefinition() => 'scalar',
      ObjectTypeDefinition() => 'type',
      InterfaceTypeDefinition() => 'interface',
      UnionTypeDefinition() => 'union',
      EnumTypeDefinition() => 'enum',
      InputObjectTypeDefinition() => 'input',
    };
    expect(
      [
        for (final type in definitions.whereType<TypeDefinition>())
          keyword(type),
      ],
      ['scalar', 'type', 'interface', 'union', 'enum', 'input'],
    );
  });
}
