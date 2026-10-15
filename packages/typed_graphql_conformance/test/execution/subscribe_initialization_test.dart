import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from the "Subscription Initialization Phase" tests of graphql-js
// src/execution/__tests__/subscribe-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. The source of a subscription field
// is declared on the field (graphql-js reads it from the root value or from
// `subscribe`), and `subscribe` answers a rejected request with a value
// where graphql-js throws.
void main() {
  const port = ExecutionPort();

  ExecutableSchema<Object?> schemaOf(
    List<FieldDef<Object?, Object?>> Function(
      ExecutableSchemaBuilder<Object?> b,
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) {
    final b = ExecutableSchemaBuilder<Object?>();
    return b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [t.field('dummy', b.string.nullable).pure((_) => null)],
      ),
      subscription: b.object<Object?>(
        'Subscription',
        fields: (t) => fields(b, t),
      ),
    );
  }

  Future<SubscriptionResult> start(
    ExecutableSchema<Object?> schema,
    String text, {
    Object? rootValue,
    JsonObject? variables,
  }) async => port.subscribe<Object?>(
    schema,
    text,
    context: null,
    variables: variables,
    options: ExecutionOptions(rootValue: rootValue, maskErrors: false),
  );

  Future<List<Map<String, Object?>>> resultsOf(SubscriptionResult started) =>
      switch (started) {
        SubscriptionStarted(:final results) =>
          results.map(port.withoutCodes).toList(),
        SubscriptionRejected(:final error) => throw StateError('$error'),
      };

  Map<String, Object?> rejection(SubscriptionResult started) =>
      switch (started) {
        SubscriptionRejected(:final error) => port.withoutCodes(error),
        SubscriptionStarted() => throw StateError('started'),
      };

  Stream<Map<String, Object?>> fooValue() =>
      Stream.value(<String, Object?>{'foo': 'FooValue'});

  final fooSchema = schemaOf(
    (b, t) => [
      t
          .field('foo', b.string.nullable)
          .subscribeWith<Map<String, Object?>>(
            (parent, args, context, info) => fooValue(),
            (event, args, context, info) => event['foo'] as String?,
          ),
    ],
  );
  const fooResults = [
    {
      'data': {'foo': 'FooValue'},
    },
  ];

  group('Subscription Initialization Phase', () {
    test(
      'throws when subscribe is called with a non-subscription operation',
      () async {
        final started = await start(fooSchema, '{ dummy }');
        expect(rejection(started), {
          'errors': [
            {'message': 'Expected subscription operation.'},
          ],
        });
      },
    );

    test('accepts multiple subscription fields defined in schema', () async {
      final schema = schemaOf(
        (b, t) => [
          for (final name in ['foo', 'bar'])
            t
                .field(name, b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) => fooValue(),
                  (event, args, context, info) => event['foo'] as String?,
                ),
        ],
      );

      final started = await start(schema, 'subscription { foo }');

      expect(await resultsOf(started), fooResults);
    });

    test('accepts type definition with sync subscribe function', () async {
      final started = port.subscribe<Object?>(
        fooSchema,
        'subscription { foo }',
        context: null,
      );

      expect(started, isNot(isA<Future<Object?>>()));
      expect(await resultsOf(await started), fooResults);
    });

    test('accepts type definition with async subscribe function', () async {
      final schema = schemaOf(
        (b, t) => [
          t.field('foo', b.string.nullable).subscribeWith<Map<String, Object?>>(
            (parent, args, context, info) async {
              await Future<void>.delayed(Duration.zero);
              return fooValue();
            },
            (event, args, context, info) => event['foo'] as String?,
          ),
        ],
      );

      final promise = port.subscribe<Object?>(
        schema,
        'subscription { foo }',
        context: null,
      );

      expect(promise, isA<Future<Object?>>());
      expect(await resultsOf(await promise), fooResults);
    });

    test(
      'should only resolve the first field of invalid multi-field',
      () async {
        var fooCalls = 0;
        var barCalls = 0;
        final schema = schemaOf(
          (b, t) => [
            t
                .field('foo', b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) {
                    fooCalls++;
                    return fooValue();
                  },
                  (event, args, context, info) => event['foo'] as String?,
                ),
            t
                .field('bar', b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) {
                    barCalls++;
                    return const Stream.empty();
                  },
                  (event, args, context, info) => null,
                ),
          ],
        );

        final started = await start(schema, 'subscription { foo bar }');

        expect(fooCalls, 1);
        expect(barCalls, 0);
        final results = await resultsOf(started);
        expect(results, hasLength(1));
        expect(results.single['data'], containsPair('foo', 'FooValue'));
      },
    );

    test(
      'resolves to an error if schema does not support subscriptions',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('dummy', b.string.nullable).pure((_) => null),
            ],
          ),
        );

        final started = await start(schema, 'subscription { unknownField }');

        expect(rejection(started), {
          'errors': [
            {
              'message':
                  'Schema is not configured to execute subscription operation.',
            },
          ],
        });
      },
    );

    test('resolves to an error for unknown subscription field', () async {
      final started = await start(fooSchema, 'subscription { unknownField }');

      expect(rejection(started), {
        'errors': [
          {
            'message': 'The subscription selects no root field.',
          },
        ],
      });
    });

    test('resolves to an error for subscription resolver errors', () async {
      final expected = {
        'errors': [
          {
            'message': 'test error',
            'locations': [
              {'line': 1, 'column': 16},
            ],
            'path': ['foo'],
          },
        ],
      };
      ExecutableSchema<Object?> failing(
        FutureOr<Stream<String>> Function() source,
      ) => schemaOf(
        (b, t) => [
          t
              .field('foo', b.string.nullable)
              .subscribe((parent, args, context, info) => source()),
        ],
      );

      // Throwing an error
      expect(
        rejection(
          await start(
            failing(() => throw const GraphQLException('test error')),
            'subscription { foo }',
          ),
        ),
        expected,
      );
      // Rejecting with an error
      expect(
        rejection(
          await start(
            failing(
              () => Future<Stream<String>>.error(
                const GraphQLException('test error'),
              ),
            ),
            'subscription { foo }',
          ),
        ),
        expected,
      );
    });

    test('resolves to an error if variables were wrong type', () async {
      final schema = schemaOf(
        (b, t) => [
          t
              .field(
                'foo',
                b.string.nullable,
                args: [Arg('arg', b.int.nullable)],
              )
              .subscribe((parent, args, context, info) => Stream.value('x')),
        ],
      );

      // If we receive variables that cannot be coerced correctly, subscribe()
      // will resolve to an ExecutionResult that contains an informative error
      // description.
      final started = await start(
        schema,
        r'''

      subscription ($arg: Int) {
        foo(arg: $arg)
      }
    ''',
        variables: port.variablesOf({'arg': 'meow'}),
      );

      expect(rejection(started), {
        'errors': [
          {
            'message': r'Variable "$arg" has invalid value: Int cannot represent non-integer value: "meow"',
            'locations': [
              {'line': 2, 'column': 21},
            ],
          },
        ],
      });
    });
  });
}
