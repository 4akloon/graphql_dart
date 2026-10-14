import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('operations', () {
    test('a shorthand query is an anonymous query', () {
      final operation = Parsed('{ a }').single<OperationDefinition>();
      expect(operation.operation, OperationType.query);
      expect(operation.name, isNull);
      expect([operation.start, operation.end], [0, 5]);
    });

    test('parses every operation type, named or not', () {
      final document = Parsed(
        'query { a } mutation M { b } subscription S { c }',
      ).document;
      final operations = document.definitions.cast<OperationDefinition>();
      expect(operations.map((operation) => operation.operation), [
        OperationType.query,
        OperationType.mutation,
        OperationType.subscription,
      ]);
      expect(operations.map((operation) => operation.name?.value), [
        null,
        'M',
        'S',
      ]);
    });

    test('parses descriptions, variables, defaults and directives', () {
      final operation = Parsed(
        r'"Op" query Q("V" $v: [Int!] = [1] @d, $w: String) @e { a }',
      ).single<OperationDefinition>();
      expect(operation.description?.value, 'Op');
      final variables = operation.variableDefinitions;
      expect(variables.map((variable) => variable.variable.name.value), [
        'v',
        'w',
      ]);
      expect(variables.first.description?.value, 'V');
      expect(variables.first.defaultValue, isA<ListValue>());
      expect(variables.first.directives.single.name.value, 'd');
      expect(operation.directives.single.name.value, 'e');
    });

    test('a variable default value is constant', () {
      expect(Parsed(r'query ($a: Int = $b) { a }').errors, [
        r'1:18 GQL009 Unexpected variable "$b" in constant value.',
      ]);
    });
  });

  group('selections', () {
    test('parses aliases, arguments, directives and nested sets', () {
      final operation = Parsed(
        r'{ x: a(b: $c, d: {e: 1}) @f(g: true) { h } }',
      ).single<OperationDefinition>();
      final field = operation.selectionSet.selections.single as Field;
      expect(field.alias?.value, 'x');
      expect(field.name.value, 'a');
      expect(field.arguments.map((argument) => argument.name.value), [
        'b',
        'd',
      ]);
      expect(
        field.directives.single.arguments.single.value,
        isA<BooleanValue>(),
      );
      expect(field.selectionSet?.selections.single, isA<Field>());
      expect([field.start, field.end], [2, 42]);
    });

    test('parses fragment spreads and inline fragments', () {
      final operation = Parsed(
        '{ ...F @d ... on T { a } ... @e { b } }',
      ).single<OperationDefinition>();
      final selections = operation.selectionSet.selections;
      expect((selections[0] as FragmentSpread).name.value, 'F');
      expect((selections[1] as InlineFragment).typeCondition?.name.value, 'T');
      expect((selections[2] as InlineFragment).typeCondition, isNull);
      expect((selections[2] as InlineFragment).directives, hasLength(1));
    });

    test('rejects an empty selection set unless allowed', () {
      expect(Parsed('{ }').errors, [
        '1:3 GQL012 Unexpected empty selection set.',
      ]);
      const options = ParserOptions(allowEmptySelectionSets: true);
      final operation = Parsed(
        '{ a { } }',
        options: options,
      ).single<OperationDefinition>();
      final field = operation.selectionSet.selections.single as Field;
      expect(field.selectionSet?.selections, isEmpty);
    });
  });

  group('fragments', () {
    test('parses a described fragment definition', () {
      final fragment = Parsed(
        '"F" fragment F on T @d { a }',
      ).single<FragmentDefinition>();
      expect(fragment.description?.value, 'F');
      expect(fragment.typeCondition.name.value, 'T');
      expect(fragment.directives.single.name.value, 'd');
    });

    test('rejects a fragment named on and a missing type condition', () {
      expect(Parsed('fragment on on T { a }').errors, [
        '1:10 GQL008 Unexpected Name "on".',
      ]);
      expect(Parsed('{ ...MissingOn }\nfragment MissingOn Type').errors, [
        '2:20 GQL007 Expected "on", found Name "Type".',
      ]);
    });
  });

  group('document', () {
    test('an empty document is an error', () {
      expect(Parsed('').errors, ['1:1 GQL008 Unexpected <EOF>.']);
    });

    test('reports misplaced descriptions', () {
      expect(Parsed('"d" { a }').errors, [
        '1:1 GQL011 Unexpected description, descriptions are not supported '
            'on shorthand queries.',
      ]);
      expect(Parsed('"d" foo').errors, [
        '1:1 GQL011 Unexpected description, only GraphQL definitions '
            'support descriptions.',
      ]);
    });

    test('the document spans the whole source', () {
      final document = Parsed(' { a } ').document;
      expect([document.start, document.end], [0, 7]);
    });

    test('requireDocument throws with every diagnostic on failure', () {
      final result = Parsed('{').result;
      expect(
        result.requireDocument,
        throwsA(
          isA<GraphQLSyntaxException>().having(
            (exception) => exception.diagnostics,
            'diagnostics',
            result.diagnostics,
          ),
        ),
      );
      expect(Parsed('{ a }').result.requireDocument(), isA<Document>());
    });
  });
}
