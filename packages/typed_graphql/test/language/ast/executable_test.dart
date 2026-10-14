import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const id = Name('id');
  const alias = Name('key');
  final skip = Directive(
    const Name('skip'),
    arguments: const [Argument(Name('if'), Variable(Name('no')))],
  );

  OperationDefinition operation({OperationType type = .query}) =>
      OperationDefinition(
        type,
        SelectionSet([Field(null, id)]),
        description: const StringValue('Reads.'),
        name: const Name('Q'),
        variableDefinitions: [
          VariableDefinition(
            const Variable(Name('no')),
            const NonNullType(NamedType(Name('Boolean'))),
            description: const StringValue('Skip?'),
            defaultValue: const BooleanValue(false),
            directives: [skip],
          ),
        ],
        directives: [skip],
        start: 2,
        end: 40,
      );

  group('Field', () {
    test('lists alias, name, arguments, directives, selections', () {
      final selections = SelectionSet([Field(null, id)]);
      final field = Field(
        alias,
        const Name('node'),
        arguments: const [Argument(Name('id'), IntValue('4'))],
        directives: [skip],
        selectionSet: selections,
      );
      expect(field.children, [
        same(alias),
        isA<Name>(),
        isA<Argument>(),
        same(skip),
        same(selections),
      ]);
    });

    test('withChildren reads one leading name as the name alone', () {
      final field = Field(alias, id).withChildren(const [Name('other')]);
      expect(field, isA<Field>().having((f) => f.alias, 'alias', isNull));
    });

    test('withChildren reads two leading names as alias and name', () {
      final field = Field(null, id).withChildren(const [alias, id]);
      expect(field, isA<Field>().having((f) => f.alias, 'alias', same(alias)));
    });

    test('withChildren rejects a field without a name', () {
      expect(() => Field(null, id).withChildren(const []), throwsStateError);
    });

    test('withChildren rejects three leading names', () {
      expect(
        () => Field(null, id).withChildren(const [alias, id, id]),
        throwsStateError,
      );
    });
  });

  group('executable nodes', () {
    test('withChildren rebuilds every kind of executable node', () {
      final selections = SelectionSet([
        Field(alias, id, directives: [skip], start: 1, end: 9),
        FragmentSpread(const Name('F'), directives: [skip]),
        InlineFragment(
          const NamedType(Name('User')),
          SelectionSet([Field(null, id)]),
          directives: [skip],
        ),
        InlineFragment(null, SelectionSet([Field(null, id)])),
      ]);
      final nodes = <Node>[
        selections,
        operation(),
        OperationDefinition(.mutation, selections),
        FragmentDefinition(
          const Name('F'),
          const NamedType(Name('User')),
          selections,
          description: const StringValue('Fields.'),
          directives: [skip],
        ),
        Document([operation()], start: 0, end: 41),
      ];
      nodes.forEach(check.expectRebuilds);
    });

    test('an operation lists description, name, variables, directives', () {
      final children = operation().children;
      expect(children, [
        isA<StringValue>(),
        isA<Name>(),
        isA<VariableDefinition>(),
        isA<Directive>(),
        isA<SelectionSet>(),
      ]);
    });

    test('a variable definition lists description first', () {
      final variable = operation().variableDefinitions.single;
      expect(variable.children, [
        isA<StringValue>(),
        isA<Variable>(),
        isA<NonNullType>(),
        isA<BooleanValue>(),
        isA<Directive>(),
      ]);
    });

    test('isEquivalentTo compares the operation type', () {
      expect(operation().isEquivalentTo(operation()), isTrue);
      expect(
        operation().isEquivalentTo(operation(type: .subscription)),
        isFalse,
      );
    });

    test('a document copies its definitions into an unmodifiable list', () {
      final definitions = <Definition>[operation()];
      final document = Document(definitions);
      definitions.clear();
      expect(document.definitions, hasLength(1));
      expect(document.definitions.clear, throwsUnsupportedError);
    });
  });
}
