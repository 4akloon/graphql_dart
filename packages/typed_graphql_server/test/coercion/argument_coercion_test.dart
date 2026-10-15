import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/argument_coercion.dart';
import 'package:typed_graphql_server/src/coercion/coercion_problems.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/input_path.dart';
import 'package:typed_graphql_server/src/coercion/invalid_value.dart';
import 'package:typed_graphql_server/src/coercion/literal_coercion.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  final coercion = ArgumentCoercion(fx.environment);

  Field fieldOf(String query) =>
      (const Parser().parse(Source(query)).requireDocument().definitions.single
                  as OperationDefinition)
              .selectionSet
              .selections
              .single
          as Field;

  // The result of `{ [call] }` against Query.[name]; [variables] are coerced.
  CoercionResult run(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) {
    final query = fx.schema.typeNamed('Query')! as ObjectType;
    return coercion.coerce(
      'Query.$name',
      query.fieldNamed(name)!.arguments,
      fieldOf('{ $call }').arguments,
      variables,
    );
  }

  Map<String, Object?> valuesOf(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(name, call, variables)) {
    CoercionSuccess(value: final Map<String, Object?> values) => values,
    CoercionSuccess() => fail('not a map'),
    CoercionFailure(:final problems) => fail(
      'failed: ${problems.map((p) => p.message).toList()}',
    ),
  };

  String messageOf(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(name, call, variables)) {
    CoercionSuccess() => fail('expected a failure'),
    CoercionFailure(:final problems) => problems.single.message,
  };

  group('values', () {
    test('coerces the literals of scalars', () {
      expect(valuesOf('typed', 'typed(req: 3, opt: "x", flag: true)'), {
        'req': 3,
        'opt': 'x',
        'flag': true,
        'limit': 10,
      });
    });

    test('keeps an explicit null', () {
      expect(valuesOf('typed', 'typed(req: 1, opt: null)')['opt'], isNull);
      expect(valuesOf('typed', 'typed(req: 1, opt: null)'), contains('opt'));
    });

    test('applies the default of an argument that is not given', () {
      expect(valuesOf('typed', 'typed(req: 1)')['limit'], 10);
    });

    test('leaves out an optional argument without a default', () {
      expect(valuesOf('typed', 'typed(req: 1)'), isNot(contains('opt')));
    });

    test('maps an enum literal by name', () {
      expect(
        valuesOf('typed', 'typed(req: 1, color: green)')['color'],
        Color.green,
      );
    });

    test('wraps a single item as a list', () {
      expect(valuesOf('typed', 'typed(req: 1, ids: 7)')['ids'], [7]);
    });

    test('reads a list literal', () {
      expect(valuesOf('typed', 'typed(req: 1, ids: [1, 2])')['ids'], [1, 2]);
    });

    test('runs the codec of a custom scalar on its literal', () {
      expect(
        valuesOf('typed', 'typed(req: 1, big: "ExternalValue")')['big'],
        'InternalValue',
      );
    });

    test('decodes an input object literal', () {
      expect(
        valuesOf('probe', 'probe(input: {a: "x", c: "y"})')['input'],
        containsPair('c', 'y'),
      );
    });

    test('fills the defaults of input fields', () {
      expect(valuesOf('probe', 'probe(defaulted: {})')['defaulted'], {
        'count': 5,
        'shade': Color.green,
        'tags': isNull,
      });
    });
  });

  group('variables', () {
    test('substitutes a coerced variable', () {
      expect(
        valuesOf('typed', r'typed(req: $n)', {'n': 4})['req'],
        4,
      );
    });

    test('treats a missing optional variable as not given', () {
      expect(
        valuesOf('typed', r'typed(req: 1, limit: $l)', {})['limit'],
        10,
      );
    });

    test('keeps a variable that is null', () {
      expect(
        valuesOf('typed', r'typed(req: 1, opt: $o)', {'o': null}),
        containsPair('opt', isNull),
      );
    });

    test('substitutes a variable inside a list and an object', () {
      expect(
        valuesOf('typed', r'typed(req: 1, ids: [1, $n])', {'n': 2})['ids'],
        [1, 2],
      );
      expect(
        valuesOf('probe', r'probe(input: {c: $c})', {'c': 'v'})['input'],
        containsPair('c', 'v'),
      );
    });

    test('reads a missing variable in a list as null', () {
      expect(
        valuesOf('probe', r'probe(input: {c: "x", b: ["a", $b]})')['input'],
        containsPair('b', ['a', null]),
      );
    });

    test('uses the default of an input field for a missing variable', () {
      expect(
        valuesOf('probe', r'probe(defaulted: {count: $c})')['defaulted'],
        containsPair('count', 5),
      );
    });
  });

  group('messages', () {
    test('a required argument that was not provided', () {
      expect(
        messageOf('typed', 'typed'),
        'Argument "Query.typed(req:)" of required type "Int!" was not '
        'provided.',
      );
    });

    test('a required argument whose variable has no value', () {
      expect(
        messageOf('typed', r'typed(req: $n)'),
        'Argument "Query.typed(req:)" has invalid value: Expected variable '
        r'"$n" provided to type "Int!" to provide a runtime value.',
      );
    });

    test('a required argument whose variable is null', () {
      expect(
        messageOf('typed', r'typed(req: $n)', {'n': null}),
        'Argument "Query.typed(req:)" has invalid value: Expected variable '
        r'"$n" provided to non-null type "Int!" not to be null.',
      );
    });

    test('a null literal for a non-null argument', () {
      expect(
        messageOf('typed', 'typed(req: null)'),
        'Argument "Query.typed(req:)" has invalid value: Expected value of '
        'non-null type "Int!" not to be null.',
      );
    });

    test('a literal of the wrong kind', () {
      expect(
        messageOf('typed', 'typed(req: "x")'),
        'Argument "Query.typed(req:)" has invalid value: Int cannot '
        'represent non-integer value: "x"',
      );
    });

    test('a float literal for an Int', () {
      expect(
        messageOf('typed', 'typed(req: 1.0)'),
        'Argument "Query.typed(req:)" has invalid value: Int cannot '
        'represent non-integer value: 1.0',
      );
    });

    test('an enum literal for a String names the argument', () {
      expect(
        messageOf('typed', 'typed(req: 1, opt: RED)'),
        'Argument "Query.typed(opt:)" has invalid value: String cannot '
        'represent a non string value: RED',
      );
    });

    test('a string literal for an enum', () {
      expect(
        messageOf('typed', 'typed(req: 1, color: "green")'),
        'Argument "Query.typed(color:)" has invalid value: Enum "Color" '
        'cannot represent non-enum value: "green". Did you mean the enum value '
        '"green"?',
      );
    });

    test('an unknown enum value', () {
      expect(
        messageOf('typed', 'typed(req: 1, color: grene)'),
        'Argument "Query.typed(color:)" has invalid value: Value "grene" '
        'does not exist in "Color" enum. Did you mean the enum value '
        '"green" or "red"?',
      );
    });

    test('a path into a list', () {
      expect(
        messageOf('typed', 'typed(req: 1, ids: [1, "x"])'),
        'Argument "Query.typed(ids:)" has invalid value at [1]: Int cannot '
        'represent non-integer value: "x"',
      );
    });

    test('a value that is not an object', () {
      expect(
        messageOf('probe', 'probe(input: [1])'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" to be an object, found: [1].',
      );
    });

    test('a missing required field', () {
      expect(
        messageOf('probe', 'probe(input: {a: "x"})'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" to include required field "c", found: '
        '{ a: "x" }.',
      );
    });

    test('an unknown field with a suggestion', () {
      expect(
        messageOf('probe', 'probe(input: {c: "x", aa: "y"})'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" not to include unknown field "aa". Did '
        'you mean "a"? Found: { c: "x", aa: "y" }.',
      );
    });

    test('a faulty scalar inside an object names the path', () {
      expect(
        messageOf('probe', 'probe(input: {c: "x", e: "y"})'),
        'Argument "Query.probe(input:)" has invalid value at .e: '
        'FaultyScalarErrorMessage',
      );
    });

    test('a oneOf object with two fields', () {
      expect(
        messageOf('probe', 'probe(lookup: {id: 1, email: "a"})'),
        'Argument "Query.probe(lookup:)" has invalid value: Within OneOf '
        'Input Object type "Lookup", exactly one field must be specified, '
        'and the value for that field must be non-null.',
      );
    });

    test('a oneOf field that is a null literal', () {
      expect(
        messageOf('probe', 'probe(lookup: {id: null})'),
        'Argument "Query.probe(lookup:)" has invalid value at .id: Within '
        'OneOf Input Object type "Lookup", exactly one field must be '
        'specified, and the value for that field must be non-null.',
      );
    });

    test('a oneOf field whose variable is null', () {
      expect(
        messageOf('probe', r'probe(lookup: {id: $a})', {'a': null}),
        'Argument "Query.probe(lookup:)" has invalid value: Expected '
        r'variable "$a" provided to field "id" for OneOf Input Object type '
        '"Lookup" not to be null.',
      );
    });

    test('a oneOf field whose variable has no value', () {
      expect(
        messageOf('probe', r'probe(lookup: {id: $a})'),
        'Argument "Query.probe(lookup:)" has invalid value: Expected '
        r'variable "$a" provided to field "id" for OneOf Input Object type '
        '"Lookup" to provide a runtime value.',
      );
    });
  });

  group('failures', () {
    test('stop at the first failing argument', () {
      final result = run('typed', 'typed(req: "x", opt: RED)');
      expect(result, isA<CoercionFailure>());
      expect((result as CoercionFailure).problems, hasLength(1));
    });

    test('carry GQL313', () {
      final result = run('typed', 'typed(req: "x")') as CoercionFailure;
      expect(result.problems.single.code, DiagnosticCode.invalidArgumentValue);
    });

    test('keep the extensions of a GraphQLException from decode', () {
      final result = run('more', 'more(exploding: {})') as CoercionFailure;
      final problem = result.problems.single;
      expect(
        problem.message,
        'Argument "Query.more(exploding:)" has invalid value: refused',
      );
      expect(problem.extensions, isNotNull);
    });

    test('keep what decode threw for onError and use GQL314', () {
      final result = run('more', 'more(crashing: {})') as CoercionFailure;
      final problem = result.problems.single;
      expect(problem.code, DiagnosticCode.inputDecodeFailed);
      expect(problem.thrown?.error, isA<StateError>());
      expect(problem.message, isNot(contains('secret detail')));
    });

    test('stop a literal nested deeper than the bound', () {
      // Built in code: the parser's own depth limit would refuse it.
      Value literal = ObjectValue([]);
      for (var i = 0; i < 1100; i++) {
        literal = ObjectValue([ObjectField(const Name('next'), literal)]);
      }
      final problems = CoercionProblems(1);
      final result = LiteralCoercion(
        fx.environment,
        problems,
        const <String, Object?>{},
      ).coerce(literal, fx.type('Chain'), InputPath.root, 0);
      expect(result, InvalidValue.instance);
      expect(problems.kept.single.message, 'Input value is nested too deeply.');
    });
  });
}
