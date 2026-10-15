import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputLiteral, the OneOf Input Object cases); each case writes the
// literal as the argument of a field and compares the errors of the
// response. mapping/execution.csv says which tests are adapted or skipped,
// and why.
void main() {
  final ob = ExecutableSchemaBuilder<Object?>();
  final oneOfFoo = Arg.optional('foo', ob.int.nullable);
  final oneOfBar = Arg.optional('bar', ob.int.nullable);
  final oneOf = ob.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final oneOfProbe = InputProbe(ob, [
    ('oneOf', 'TestInputObject', oneOf.nullable),
  ]);
  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';
  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';
  const intVariable = r'($var: Int)';

  group('validateInputLiteral', () {
    group('for GraphQLInputObject that isOneOf', () {
      Future<List<String>> literal(
        String text, {
        String definitions = '',
        Map<String, Object?> variables = const {},
      }) => oneOfProbe.literalErrors(
        'oneOf',
        text,
        definitions: definitions,
        variables: variables,
      );
      String error(String message, [String path = '']) =>
          oneOfProbe.argumentError('oneOf', message, path);

      test('returns no error for a valid input', () async {
        expect(await literal('{ foo: 123 }'), isEmpty);
      });

      test('returns an error if more than one field is specified', () async {
        expect(await literal('{ foo: 123, bar: null }'), [error(badOneOf)]);
      });

      test('returns an error if the one field is null', () async {
        expect(await literal('{ bar: null }'), [error(badOneOf, '.bar')]);
      });

      test('returns an error for a non-object type', () async {
        expect(await literal('123'), [error('${wrongObject}123.')]);
      });

      test('returns an error for an invalid field', () async {
        expect(await literal('{ foo: 1.5 }'), [
          error('Int cannot represent non-integer value: 1.5', '.foo'),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(await literal('{ foo: 123, unknownField: 123 }'), [
          error(
            '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field', () async {
        expect(await literal('{ foo: 123, bart: 123 }'), [
          error(
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('allows variables in an object, statically', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 1},
          ),
          isEmpty,
        );
      });

      test('allows correct use of variables', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 123},
          ),
          isEmpty,
        );
      });

      test('returns error with variable provided a value of null', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            error(
              r'Expected variable "$var" provided to field "foo" for OneOf Input Object type "TestInputObject" not to be null.',
            ),
          ],
        );
      });

      test('errors with missing variables as the additional field', () async {
        const missing =
            r'Expected variable "$var" provided to field "bar" for OneOf Input Object type "TestInputObject" to provide a runtime value.';
        // An argument reports its first problem only; graphql-js reports
        // every one.
        expect(await literal(r'{ foo: 123, bar: $var }'), [error(missing)]);
        expect(
          await literal(r'{ foo: 123, bar: $var }', definitions: intVariable),
          [error(missing)],
        );
      });

      test('errors with multiple variables when one is missing', () async {
        expect(
          await literal(
            r'{ foo: $foo, bar: $bar }',
            definitions: r'($foo: Int, $bar: Int)',
            variables: {'foo': 123},
          ),
          [
            error(
              r'Expected variable "$bar" provided to field "bar" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            ),
          ],
        );
      });
    });
  });
}
