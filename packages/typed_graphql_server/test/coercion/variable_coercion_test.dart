import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/variable_coercion.dart';
import 'package:typed_graphql_server/src/coercion/variable_coercion_result.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();

  VariableCoercionResult run(
    String query,
    String? variables, {
    int maxErrors = 50,
  }) => VariableCoercion(fx.coercion, maxCoercionErrors: maxErrors).coerce(
    fx.variables(query),
    variables == null ? null : fx.json(variables) as JsonObject,
    source: Source(query),
  );

  Map<String, Object?> valuesOf(String query, String? variables) =>
      switch (run(query, variables)) {
        CoercedVariables(:final values) => values,
        VariableCoercionFailure(:final errors) => fail(
          'failed: ${errors.map((error) => error.message).toList()}',
        ),
      };

  List<GraphQLError> errorsOf(
    String query,
    String? variables, {
    int maxErrors = 50,
  }) => switch (run(query, variables, maxErrors: maxErrors)) {
    CoercedVariables() => fail('expected errors'),
    VariableCoercionFailure(:final errors) => errors,
  };

  List<String> messagesOf(String query, String? variables) => [
    for (final error in errorsOf(query, variables)) error.message,
  ];

  group('values', () {
    test('coerces a provided value', () {
      expect(
        valuesOf(r'query ($value: Int) { a }', '{"value": 3}'),
        {'value': 3},
      );
    });

    test('omits a nullable variable that was not provided', () {
      expect(valuesOf(r'query ($value: String) { a }', '{}'), isEmpty);
    });

    test('works without any variables object', () {
      expect(valuesOf(r'query ($value: String) { a }', null), isEmpty);
    });

    test('keeps an explicit null', () {
      expect(
        valuesOf(r'query ($value: String) { a }', '{"value": null}'),
        {'value': null},
      );
    });

    test('uses the default when the variable is not provided', () {
      expect(
        valuesOf(r'query ($value: String = "default") { a }', '{}'),
        {'value': 'default'},
      );
    });

    test('uses a null default', () {
      expect(
        valuesOf(r'query ($value: String = null) { a }', '{}'),
        {'value': null},
      );
    });

    test('prefers the provided value over the default', () {
      expect(
        valuesOf(r'query ($value: String = "d") { a }', '{"value": "v"}'),
        {'value': 'v'},
      );
    });

    test('an explicit null replaces the default', () {
      expect(
        valuesOf(r'query ($value: String = "d") { a }', '{"value": null}'),
        {'value': null},
      );
    });

    test('a non-null variable is satisfied by its default', () {
      expect(
        valuesOf(r'query ($value: String! = "d") { a }', '{}'),
        {'value': 'd'},
      );
    });

    test('a single value is a list of one', () {
      expect(
        valuesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": "baz"}}',
        ),
        {
          'input': {
            'a': 'foo',
            'b': ['bar'],
            'c': 'baz',
            'd': null,
            'e': null,
          },
        },
      );
    });

    test('an object default is coerced from its literal', () {
      final values = valuesOf(
        r'query ($input: TestInputObject = {a: "foo", b: ["bar"], c: "baz"}) { a }',
        '{}',
      );
      expect((values['input']! as Map<String, Object?>)['c'], 'baz');
    });
  });

  group('invalid values', () {
    test('a missing required variable', () {
      final errors = errorsOf(r'query ($value: String!) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$value" has invalid value: Expected a value of '
        'non-null type "String!" to be provided.',
      );
      expect(errors.single.locations.single.line, 1);
      expect(errors.single.locations.single.column, 8);
      expect(
        errors.single.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.invalidVariableValue.id),
        }),
      );
    });

    test('null for a non-null variable', () {
      expect(messagesOf(r'query ($value: String!) { a }', '{"value": null}'), [
        r'Variable "$value" has invalid value: Expected value of non-null '
            'type "String!" not to be null.',
      ]);
    });

    test('null for a non-null list', () {
      expect(
        messagesOf(r'query ($input: [String]!) { a }', '{"input": null}'),
        [
          r'Variable "$input" has invalid value: Expected value of '
              'non-null type "[String]!" not to be null.',
        ],
      );
    });

    test('null in a list of non-null items', () {
      expect(
        messagesOf(
          r'query ($input: [String!]) { a }',
          '{"input": ["A", null, "B"]}',
        ),
        [
          r'Variable "$input" has invalid value at [1]: Expected value of '
              'non-null type "String!" not to be null.',
        ],
      );
    });

    test('a value of the wrong scalar type', () {
      expect(messagesOf(r'query ($value: String!) { a }', '{"value": 123}'), [
        r'Variable "$value" has invalid value: String cannot represent a '
            'non string value: 123',
      ]);
    });

    test('a value that is not an object', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": "foo bar"}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" to be an object, found: "foo bar".',
        ],
      );
    });

    test('a faulty scalar field names its path', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"c": "foo", "e": "ExternalValue"}}',
        ),
        [
          r'Variable "$input" has invalid value at .e: FaultyScalarErrorMessage',
        ],
      );
    });

    test('null for a nested non-null field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": null}}',
        ),
        [
          r'Variable "$input" has invalid value at .c: Expected value of '
              'non-null type "String!" not to be null.',
        ],
      );
    });

    test('an omitted nested required field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar"}}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" to include required field "c", found: '
              '{ a: "foo", b: "bar" }.',
        ],
      );
    });

    test('deep nested errors are all reported', () {
      expect(
        messagesOf(
          r'query ($input: TestNestedInputObject) { a }',
          '{"input": {"na": {"a": "foo"}}}',
        ),
        [
          r'Variable "$input" has invalid value at .na: Expected value of '
              'type "TestInputObject" to include required field "c", found: '
              '{ a: "foo" }.',
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestNestedInputObject" to include required field "nb", '
              'found: { na: { a: "foo" } }.',
        ],
      );
    });

    test('an unknown input field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": "baz", "extra": "dog"}}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" not to include unknown field "extra", '
              'found: { a: "foo", b: "bar", c: "baz", extra: "dog" }.',
        ],
      );
    });

    test('an enum name that does not exist', () {
      expect(messagesOf(r'query ($c: Color) { a }', '{"c": "blue"}'), [
        r'Variable "$c" has invalid value: Value "blue" does not exist in '
            '"Color" enum.',
      ]);
    });

    test('a type that is not an input type', () {
      final errors = errorsOf(r'query ($input: Query!) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$input" expected value of type "Query!" which cannot '
        'be used as an input type.',
      );
      expect(errors.single.locations.single.column, 16);
    });

    test('an unknown type', () {
      expect(messagesOf(r'query ($input: UnknownType!) { a }', '{}'), [
        r'Variable "$input" expected value of type "UnknownType!" which '
            'cannot be used as an input type.',
      ]);
    });

    test('an error of decode keeps its extensions and has no GQL code', () {
      final errors = errorsOf(r'query ($x: Exploding) { a }', '{"x": {}}');
      expect(
        errors.single.message,
        r'Variable "$x" has invalid value: refused',
      );
      expect(
        errors.single.extensions,
        JsonObject({'reason': const JsonString('policy')}),
      );
    });

    test('an error thrown by decode is masked, coded GQL314 and reported', () {
      final result = run(
        r'query ($x: Crashing) { a }',
        '{"x": {}}',
      ) as VariableCoercionFailure;
      expect(
        result.errors.single.message,
        r'Variable "$x" has invalid value: Unexpected error.',
      );
      expect(
        result.errors.single.extensions,
        JsonObject({'code': JsonString(DiagnosticCode.inputDecodeFailed.id)}),
      );
      expect(result.unexpected.single.error, isA<StateError>());
      expect(result.unexpected.single.reported, result.errors.single);
    });
  });

  group('invalid defaults', () {
    test('a default of the wrong type is GQL311 at the definition', () {
      final errors = errorsOf(r'query ($input: String = 123) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$input" has invalid default value: String cannot '
        'represent a non string value: 123',
      );
      expect(errors.single.locations.single.column, 8);
      expect(
        errors.single.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.invalidVariableDefault.id),
        }),
      );
    });

    test('a default with an unknown field names it, with a suggestion', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject = {c: "ok", aa: "x"}) { a }',
          '{}',
        ),
        [
          r'Variable "$input" has invalid default value: Expected value of '
              'type "TestInputObject" not to include unknown field "aa". '
              'Did you mean "a"? Found: { c: "ok", aa: "x" }.',
        ],
      );
    });

    test('a default of a custom scalar that its codec rejects', () {
      expect(messagesOf(r'query ($v: ComplexScalar = "nope") { a }', '{}'), [
        r'Variable "$v" has invalid default value: ComplexScalar must be '
            'ExternalValue',
      ]);
    });

    test('a default is not used when the value is given and invalid', () {
      expect(
        messagesOf(r'query ($v: Int = 1) { a }', '{"v": "x"}'),
        [
          r'Variable "$v" has invalid value: Int cannot represent non-integer '
              'value: "x"',
        ],
      );
    });
  });

  group('the error limit', () {
    const query = r'query ($input: [String!]) { a }';
    final values =
        '{"input": [${List.generate(4, (i) => '${i + 1}').join(',')}]}';

    String message(int index) =>
        'Variable "\$input" has invalid value at [$index]: '
        'String cannot represent a non string value: ${index + 1}';

    test('keeps every error below the limit', () {
      expect(messagesOf(query, values), [
        for (var i = 0; i < 4; i++) message(i),
      ]);
    });

    test('keeps the errors when exactly at the limit', () {
      final errors = errorsOf(query, values, maxErrors: 4);
      expect(errors.map((error) => error.message), [
        for (var i = 0; i < 4; i++) message(i),
      ]);
    });

    test('cuts after the limit with one "Too many errors" error', () {
      final errors = errorsOf(query, values, maxErrors: 2);
      expect(errors.map((error) => error.message), [
        message(0),
        message(1),
        'Too many errors processing variables, error limit reached. '
            'Execution aborted.',
      ]);
      expect(
        errors.last.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.tooManyVariableErrors.id),
        }),
      );
    });

    test('the limit is shared between variables', () {
      final errors = errorsOf(
        r'query ($a: Int!, $b: Int!, $c: Int!) { a }',
        '{}',
        maxErrors: 2,
      );
      expect(errors, hasLength(3));
      expect(errors.last.message, startsWith('Too many errors'));
    });
  });
}
