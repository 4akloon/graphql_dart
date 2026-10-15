import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('correct field ordering despite execution order', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('a', b.string.nullable).pure((_) => 'a'),
            t
                .field('b', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('b')),
            t.field('c', b.string.nullable).pure((_) => 'c'),
            t
                .field('d', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('d')),
            t.field('e', b.string.nullable).pure((_) => 'e'),
          ],
        ),
      );

      final result = await port.json(schema, '{ a, b, c, d, e }');

      expect(
        result,
        equals({
          'data': {'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd', 'e': 'e'},
        }),
      );
      expect((result['data']! as Map<String, Object?>).keys, [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('Avoids recursion', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [t.field('a', b.string.nullable).pure((_) => 'b')],
        ),
      );

      final result = port.run(schema, '''
      {
        a
        ...Frag
        ...Frag
      }

      fragment Frag on Type {
        a,
        ...Frag
      }
    ''');

      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('ignores missing sub selections on fields', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final someType = b.object<Object?>(
        'SomeType',
        fields: (t) => [t.field('b', b.string.nullable).pure((_) => 'c')],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('a', someType.nullable).pure((_) => const Object()),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ a }'),
        equals({
          'data': {'a': <String, Object?>{}},
        }),
      );
    });

    test('does not include illegal fields in output', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Q',
          fields: (t) => [t.field('a', b.string.nullable).pure((_) => null)],
        ),
      );

      expect(
        await port.json(schema, '{ thisIsIllegalDoNotIncludeMe }'),
        equals({'data': <String, Object?>{}}),
      );
    });

    test('does not include arguments that were not set', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final a = Arg.optional('a', b.boolean.nullable);
      final bArg = Arg.optional('b', b.boolean.nullable);
      final c = Arg.optional('c', b.boolean.nullable);
      final d = Arg.optional('d', b.int.nullable);
      final e = Arg.optional('e', b.int.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t
                .field('field', b.string.nullable, args: [a, bArg, c, d, e])
                .resolve((_, args, context, info) {
                  final given = [
                    for (final (name, arg) in [
                      ('a', a),
                      ('b', bArg),
                      ('c', c),
                      ('d', d),
                      ('e', e),
                    ])
                      if (args.get(arg) case Present(:final value))
                        '$name: $value',
                  ];
                  return '{ ${given.join(', ')} }';
                }),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ field(a: true, c: false, e: 0) }'),
        equals({
          'data': {'field': '{ a: true, c: false, e: 0 }'},
        }),
      );
    });

    test('executes ignoring invalid non-executable definitions', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('foo', b.string.nullable).pure((_) => null)],
        ),
      );

      expect(
        await port.json(schema, '''
      { foo }

      type Query { bar: String }
    '''),
        equals({
          'data': {'foo': null},
        }),
      );
    });

    test('uses a custom type resolver', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> fooObject;
      final fooInterface = b.interface<Object?>(
        'FooInterface',
        fields: (t) => [t.field('bar', b.string.nullable).declareOnly()],
        resolveType: (_) => fooObject,
      );
      fooObject = b.object<Object?>(
        'FooObject',
        interfaces: [fooInterface],
        fields: (t) => [t.field('bar', b.string.nullable).pure((_) => 'bar')],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('foo', fooInterface.nullable).pure((_) => const Object()),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ foo { bar } }'),
        equals({
          'data': {
            'foo': {'bar': 'bar'},
          },
        }),
      );
      expect(
        [
          for (final type in schema.schema.schema.possibleTypes(
            schema.schema.schema.typeNamed('FooInterface')!,
          ))
            type.name,
        ],
        ['FooObject'],
      );
    });

    test('uses a different number of max coercion errors', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final email = Arg('email', b.string);
      final user = b.inputObject<Map<String, Object?>>(
        'User',
        fields: () => [email],
        decode: (values) => {'email': values.get(email)},
      );
      final data = Arg('data', user.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('dummy', b.string.nullable).pure((_) => null),
          ],
        ),
        mutation: b.object<Object?>(
          'Mutation',
          fields: (t) => [
            t
                .field('updateUser', b.string.nullable, args: [data])
                .resolve((_, args, context, info) => null),
          ],
        ),
      );
      const options = ExecutionOptions(maskErrors: false, maxCoercionErrors: 1);

      final result = await port.json(
        schema,
        r'''

      mutation ($data: User) {
        updateUser(data: $data)
      }
    ''',
        variables: JsonObject({
          'data': JsonObject({
            'email': const JsonString(''),
            'wrongArg': const JsonString('wrong'),
            'wrongArg2': const JsonString('wrong'),
            'wrongArg3': const JsonString('wrong'),
          }),
        }),
        options: options,
      );

      // Returns at least 2 errors, one for the first 'wrongArg', and one for
      // coercion limit.
      expect((result['errors']! as List<Object?>), hasLength(2));
      expect(
        result,
        equals({
          'errors': [
            {
              'message':
                  r'Variable "$data" has invalid value: Expected value of '
                  'type "User" not to include unknown field "wrongArg", '
                  'found: { email: "", wrongArg: "wrong", wrongArg2: '
                  '"wrong", wrongArg3: "wrong" }.',
              'locations': [
                {'line': 2, 'column': 17},
              ],
            },
            {
              'message':
                  'Too many errors processing variables, error limit '
                  'reached. Execution aborted.',
            },
          ],
        }),
      );
    });
  });
}
