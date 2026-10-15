import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/resolve-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: resolve function', () {
    test('default function accesses properties', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Map<String, Object?>>(
          'Query',
          fields: (t) => [
            t.field('test', b.string.nullable).pure((root) {
              return root['test'] as String?;
            }),
          ],
        ),
      );
      final result = await port.json(
        schema,
        '{ test }',
        options: const ExecutionOptions(
          maskErrors: false,
          rootValue: <String, Object?>{'test': 'testValue'},
        ),
      );
      expect(
        result,
        equals({
          'data': {'test': 'testValue'},
        }),
      );
    });

    test('default function passes args and context', () async {
      final b = ExecutableSchemaBuilder<int>();
      final addend1 = Arg('addend1', b.int.nullable);
      final schema = b.build(
        query: b.object<int>(
          'Query',
          fields: (t) => [
            t.field('test', b.int.nullable, args: [addend1]).resolve((
              base,
              args,
              addend2,
              info,
            ) {
              final int addend1Value = args.get(addend1)!;
              return base + addend1Value + addend2;
            }),
          ],
        ),
      );
      final result = await port.payload<int>(
        schema,
        '{ test(addend1: 80) }',
        context: 9,
        options: const ExecutionOptions(maskErrors: false, rootValue: 700),
      );
      expect(
        port.withoutCodes(result),
        equals({
          'data': {'test': 789},
        }),
      );
    });

    test('uses provided resolve function', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final aStr = Arg.optional('aStr', b.string.nullable);
      final aInt = Arg.optional('aInt', b.int.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('test', b.string.nullable, args: [aStr, aInt]).resolve((
              source,
              args,
              context,
              info,
            ) {
              final given = <String, Object?>{
                if (args.get(aStr) case Present(:final value)) 'aStr': value,
                if (args.get(aInt) case Present(:final value)) 'aInt': value,
              };
              return jsonEncode([source, given]);
            }),
          ],
        ),
      );

      Future<Map<String, Object?>> executeQuery(
        String query, [
        Object? rootValue,
      ]) => port.json(
        schema,
        query,
        options: ExecutionOptions(maskErrors: false, rootValue: rootValue),
      );

      expect(
        await executeQuery('{ test }'),
        equals({
          'data': {'test': '[null,{}]'},
        }),
      );
      expect(
        await executeQuery('{ test }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{}]'},
        }),
      );
      expect(
        await executeQuery('{ test(aStr: "String!") }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{"aStr":"String!"}]'},
        }),
      );
      expect(
        await executeQuery('{ test(aInt: -123, aStr: "String!") }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{"aStr":"String!","aInt":-123}]'},
        }),
      );
    });
  });
}
