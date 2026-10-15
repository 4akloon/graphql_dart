import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  const oneOfMessage =
      ': Within OneOf Input Object type "Lookup", exactly one field must be '
      'specified, and the value for that field must be non-null.';

  CoercionResult coerce(String type, String json) =>
      fx.coercion.coerceValue(fx.json(json), fx.type(type));

  Object? valueOf(String type, String json) => switch (coerce(type, json)) {
    CoercionSuccess(:final value) => value,
    CoercionFailure(:final problems) => fail('failed: ${fx.texts(problems)}'),
  };

  List<String> problemsOf(String type, String json) =>
      switch (coerce(type, json)) {
        CoercionSuccess() => fail('expected a failure'),
        CoercionFailure(:final problems) => fx.texts(problems),
      };

  group('lists and null', () {
    test('a single value stands for a list of one', () {
      expect(valueOf('[String]', '"bar"'), ['bar']);
    });

    test('a list keeps its null items when the item type allows them', () {
      expect(valueOf('[String]', '["a", null]'), ['a', null]);
    });

    test('null is null for a nullable type', () {
      expect(valueOf('String', 'null'), isNull);
    });

    test('null for a non-null type is reported', () {
      expect(problemsOf('String!', 'null'), [
        ': Expected value of non-null type "String!" not to be null.',
      ]);
    });

    test('null for a non-null list is reported with the list type', () {
      expect(problemsOf('[String]!', 'null'), [
        ': Expected value of non-null type "[String]!" not to be null.',
      ]);
    });

    test('null in a list of non-null items is reported with its index', () {
      expect(problemsOf('[String!]', '["a", null]'), [
        ' at [1]: Expected value of non-null type "String!" not to be null.',
      ]);
    });
  });

  group('leaves', () {
    test('a custom scalar decodes through its codec', () {
      expect(valueOf('ComplexScalar', '"ExternalValue"'), 'InternalValue');
    });

    test('the message of a codec failure is used as it is', () {
      expect(problemsOf('FaultyScalar', '"x"'), [': FaultyScalarErrorMessage']);
    });

    test('a built-in scalar failure uses the codec message', () {
      expect(problemsOf('String', '123'), [
        ': String cannot represent a non string value: 123',
      ]);
    });

    test('an enum value is read by name', () {
      expect(valueOf('Color', '"green"'), Color.green);
    });

    test('an unknown enum value is reported, with a suggestion', () {
      expect(problemsOf('Color', '"GREEN"'), [
        ': Value "GREEN" does not exist in "Color" enum. '
            'Did you mean the enum value "green" or "red"?',
      ]);
    });

    test('suggestions can be left out', () {
      final result = fx.hiddenSuggestions.coerceValue(
        fx.json('"GREEN"'),
        fx.type('Color'),
      );
      expect(
        fx.texts((result as CoercionFailure).problems),
        [': Value "GREEN" does not exist in "Color" enum.'],
      );
    });

    test('a non-string enum value is reported with its printed form', () {
      expect(problemsOf('Color', '1'), [
        ': Enum "Color" cannot represent non-string value: 1.',
      ]);
    });

    test('a codec that throws is a masked problem with its cause', () {
      final result = coerce('ThrowingScalar', '"x"') as CoercionFailure;
      expect(result.problems.single.message, 'Unexpected error.');
      expect(result.problems.single.code, DiagnosticCode.unexpectedError);
      expect(result.problems.single.thrown?.error, isA<StateError>());
    });
  });

  group('input objects', () {
    test('a complete object is decoded', () {
      expect(
        valueOf('TestInputObject', '{"a":"foo","b":["bar"],"c":"baz"}'),
        {
          'a': 'foo',
          'b': ['bar'],
          'c': 'baz',
          'd': null,
          'e': null,
        },
      );
    });

    test('a field with a custom scalar goes through its codec', () {
      expect(
        (valueOf('TestInputObject', '{"c":"x","d":"ExternalValue"}')
            as Map<String, Object?>)['d'],
        'InternalValue',
      );
    });

    test('a faulty scalar field is reported with its path', () {
      expect(problemsOf('TestInputObject', '{"c":"x","e":"v"}'), [
        ' at .e: FaultyScalarErrorMessage',
      ]);
    });

    test('null for a nested non-null field is reported at the field', () {
      expect(problemsOf('TestInputObject', '{"a":"foo","c":null}'), [
        ' at .c: Expected value of non-null type "String!" not to be null.',
      ]);
    });

    test('a value that is not an object is reported', () {
      expect(problemsOf('TestInputObject', '"foo bar"'), [
        ': Expected value of type "TestInputObject" to be an object, '
            'found: "foo bar".',
      ]);
    });

    test('a list is not an object', () {
      expect(problemsOf('TestInputObject', '["foo","bar","baz"]'), [
        ': Expected value of type "TestInputObject" to be an object, '
            'found: ["foo", "bar", "baz"].',
      ]);
    });

    test('a missing required field is reported with the object', () {
      expect(problemsOf('TestInputObject', '{"a":"foo","b":["bar"]}'), [
        ': Expected value of type "TestInputObject" to include required '
            'field "c", found: { a: "foo", b: ["bar"] }.',
      ]);
    });

    test('nested problems come before the problems of the parent', () {
      expect(problemsOf('TestNestedInputObject', '{"na":{"a":"foo"}}'), [
        ' at .na: Expected value of type "TestInputObject" to include '
            'required field "c", found: { a: "foo" }.',
        ': Expected value of type "TestNestedInputObject" to include '
            'required field "nb", found: { na: { a: "foo" } }.',
      ]);
    });

    test('an unknown field is reported', () {
      expect(
        problemsOf(
          'TestInputObject',
          '{"a":"foo","b":"bar","c":"baz","extra":"dog"}',
        ),
        [
          ': Expected value of type "TestInputObject" not to include '
              'unknown field "extra", found: '
              '{ a: "foo", b: "bar", c: "baz", extra: "dog" }.',
        ],
      );
    });

    test('an unknown field gets a suggestion', () {
      expect(problemsOf('TestInputObject', '{"c":"ok","aa":"x"}'), [
        ': Expected value of type "TestInputObject" not to include '
            'unknown field "aa". Did you mean "a"? Found: '
            '{ c: "ok", aa: "x" }.',
      ]);
    });

    test('suggestions for unknown fields can be left out', () {
      final result = fx.hiddenSuggestions.coerceValue(
        fx.json('{"c":"ok","aa":"x"}'),
        fx.type('TestInputObject'),
      );
      expect(fx.texts((result as CoercionFailure).problems), [
        ': Expected value of type "TestInputObject" not to include '
            'unknown field "aa", found: { c: "ok", aa: "x" }.',
      ]);
    });

    test('missing fields take their coerced defaults', () {
      expect(valueOf('Defaulted', '{}'), {
        'count': 5,
        'shade': Color.green,
        'tags': null,
      });
    });

    test('a given field wins over its default', () {
      expect(
        (valueOf('Defaulted', '{"count":7}') as Map<String, Object?>)['count'],
        7,
      );
    });
  });

  group('input objects with @oneOf', () {
    test('exactly one non-null field is accepted', () {
      expect(valueOf('Lookup', '{"id":1}'), '1/null');
    });

    test('no field is reported', () {
      expect(problemsOf('Lookup', '{}'), [oneOfMessage]);
    });

    test('two fields are reported', () {
      expect(problemsOf('Lookup', '{"id":1,"email":"a"}'), [oneOfMessage]);
    });

    test('a null field is reported at the field', () {
      expect(problemsOf('Lookup', '{"id":null}'), [' at .id$oneOfMessage']);
    });
  });

  group('decode', () {
    test('a GraphQLException becomes a problem with its message', () {
      final result = coerce('Exploding', '{}') as CoercionFailure;
      expect(result.problems.single.message, 'refused');
      expect(
        result.problems.single.extensions,
        JsonObject({'reason': const JsonString('policy')}),
      );
      expect(result.problems.single.code, isNull);
    });

    test('any other error is masked, coded GQL314 and kept as the cause', () {
      final result = coerce('Crashing', '{}') as CoercionFailure;
      expect(result.problems.single.message, 'Unexpected error.');
      expect(result.problems.single.code, DiagnosticCode.inputDecodeFailed);
      expect(result.problems.single.thrown?.error, isA<StateError>());
    });
  });

  group('limits', () {
    test(
      'at most maxProblems problems are kept, and the overflow is noted',
      () {
        final items = List.filled(100, '"x"').join(',');
        final result = fx.coercion.coerceValue(
          fx.json('[$items]'),
          fx.type('[Int]'),
          maxProblems: 3,
        ) as CoercionFailure;
        expect(result.problems, hasLength(3));
        expect(result.hasOverflowed, isTrue);
      },
    );

    test('a value nested 900 levels deep is coerced', () {
      expect(fx.chain(900), isA<CoercionSuccess>());
    });

    test('a value nested 2000 levels deep is one problem, not a crash', () {
      final result = fx.chain(2000) as CoercionFailure;
      expect(result.problems.map((problem) => problem.message), [
        'Input value is nested too deeply.',
      ]);
    });
  });

  group('literals', () {
    test('an enum literal is read by name', () {
      final result = fx.coercion.coerceLiteral(
        const EnumValue('red'),
        fx.type('Color'),
      );
      expect((result as CoercionSuccess).value, Color.red);
    });

    test('a variable in a literal is a problem', () {
      final result = fx.coercion.coerceLiteral(
        const Variable(Name('x')),
        fx.type('Int'),
      ) as CoercionFailure;
      expect(result.problems.single.message, contains(r'"$x"'));
    });
  });
}
