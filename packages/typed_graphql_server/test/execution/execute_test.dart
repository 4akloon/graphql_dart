import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();

  group('execute', () {
    test('a query of synchronous resolvers returns a non-future', () {
      final result = f.run('{ hello greet strings }');
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        (result as ExecutionResult).toJson().toJson(),
        equals({
          'data': {
            'hello': 'world',
            'greet': 'hi you',
            'strings': ['a', 'b'],
          },
        }),
      );
    });

    test('an async resolver makes the result a future', () async {
      final result = f.run('{ hello slow }');
      expect(result, isA<Future<Object?>>());
      expect(
        (await result).toJson().toJson(),
        equals({
          'data': {'hello': 'world', 'slow': 'slow'},
        }),
      );
    });

    test('async siblings keep the order of the document', () async {
      expect(
        await f.json('{ slow quick hello }'),
        equals({
          'data': {'slow': 'slow', 'quick': 'quick', 'hello': 'world'},
        }),
      );
      final data = (await f.json('{ slow quick hello }'))['data'];
      expect((data! as Map<String, Object?>).keys, ['slow', 'quick', 'hello']);
    });

    test('a single async sibling among sync ones completes', () async {
      expect(
        await f.json('{ hello quick greet }'),
        equals({
          'data': {'hello': 'world', 'quick': 'quick', 'greet': 'hi you'},
        }),
      );
    });

    test('aliases are the response keys', () async {
      expect(
        await f.json('{ a: hello b: hello }'),
        equals({
          'data': {'a': 'world', 'b': 'world'},
        }),
      );
    });

    test('__typename is answered by the executor', () async {
      expect(
        await f.json('{ __typename pet { __typename } }'),
        equals({
          'data': {
            '__typename': 'Query',
            'pet': {'__typename': 'Dog'},
          },
        }),
      );
    });

    test('arguments reach the resolver, defaults included', () async {
      expect(
        await f.json('{ a: greet(name: "ann") b: greet }'),
        equals({
          'data': {'a': 'hi ann', 'b': 'hi you'},
        }),
      );
    });

    test('variables are coerced and used', () async {
      expect(
        await f.json(
          r'query ($n: String) { greet(name: $n) }',
          variables: JsonObject({'n': const JsonString('bob')}),
        ),
        equals({
          'data': {'greet': 'hi bob'},
        }),
      );
    });

    test('the resolver sees its path, parent type and field', () async {
      expect(
        await f.json('{ x: where self { where } }'),
        equals({
          'data': {
            'x': 'x|Query|where',
            'self': {'where': 'self.where|Query|where'},
          },
        }),
      );
    });

    test('the context reaches the resolver', () async {
      final context = Ctx()..log.addAll(['a', 'b']);
      expect(
        await f.json('{ useContext }', context: context),
        equals({
          'data': {'useContext': 'a,b'},
        }),
      );
    });

    test('an operation name picks the operation', () async {
      final payload = await f.run(
        'query A { hello } query B { greet }',
        operationName: 'B',
      );
      expect(
        payload.toJson().toJson(),
        equals({
          'data': {'greet': 'hi you'},
        }),
      );
    });
  });

  group('request errors', () {
    test('an unknown operation name is a request error', () {
      final result = f.run('query A { hello }', operationName: 'Z');
      expect(result, isA<RequestErrorResult>());
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL320'),
      );
    });

    test('several operations without a name is a request error', () {
      final result = f.run('query A { hello } query B { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL321'),
      );
    });

    test('a document without operation is a request error', () {
      final result = f.run('fragment F on Query { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL322'),
      );
    });

    test('an operation type the schema lacks is a request error', () {
      final result = f.run('subscription { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL323'),
      );
    });

    test('an invalid variable value is a request error with no data', () {
      final result = f.run(
        r'query ($n: Int) { hello }',
        variables: JsonObject({'n': const JsonString('x')}),
      );
      expect(result, isA<RequestErrorResult>());
      expect(
        (result as RequestErrorResult).errors.single.message,
        r'Variable "$n" has invalid value: Int cannot represent non-integer '
        'value: "x"',
      );
    });
  });

  group('programmer errors', () {
    test('a document validated against another schema is an ArgumentError', () {
      final other = ExecutionFixture();
      expect(
        () => f.built.execute(
          other.validDocument('{ hello }'),
          context: Ctx(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a root value the root type does not accept is an ArgumentError', () {
      final b = ExecutableSchemaBuilder<Ctx>();
      final query = b.object<Ctx>(
        'Query',
        fields: (t) => [t.field('x', b.int).pure((_) => 1)],
      );
      final built = b.build(query: query);
      final document = ValidDocument.assumeValid(
        built.schema,
        f.parse('{ x }'),
      );
      expect(
        () => built.execute(document, context: Ctx()),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        built.execute(
          document,
          context: Ctx(),
          options: ExecutionOptions(rootValue: Ctx()),
        ),
        isA<ExecutionResult>(),
      );
    });
  });
}
