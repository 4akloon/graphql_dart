import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Data {
  String a() => 'Apple';

  String b() => 'Banana';

  String c() => 'Cookie';

  String d() => 'Donut';

  String e() => 'Egg';

  String get f => 'Fish';

  String pic(int? size) => 'Pic of size: $size';

  _DeepData get deep => _DeepData(this);

  Future<_Data> get promise => Future.value(this);
}

final class _DeepData {
  _DeepData(this.data);

  final _Data data;

  String a() => 'Already Been Done';

  String b() => 'Boring';

  List<String?> c() => ['Contrived', null, 'Confusing'];

  List<_Data?> deeper() => [data, null, data];
}

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('executes arbitrary code', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final size = Arg('size', b.int.nullable);
      late final ObjectTypeDef<_Data> dataType;
      final deepDataType = b.object<_DeepData>(
        'DeepDataType',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((deep) => deep.a()),
          t.field('b', b.string.nullable).pure((deep) => deep.b()),
          t
              .field('c', b.list(b.string.nullable).nullable)
              .pure((deep) => deep.c()),
          t
              .field('deeper', b.list(dataType.nullable).nullable)
              .pure((deep) => deep.deeper()),
        ],
      );
      dataType = b.object<_Data>(
        'DataType',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((data) => data.a()),
          t.field('b', b.string.nullable).pure((data) => data.b()),
          t.field('c', b.string.nullable).pure((data) => data.c()),
          t.field('d', b.string.nullable).pure((data) => data.d()),
          t.field('e', b.string.nullable).pure((data) => data.e()),
          t.field('f', b.string.nullable).pure((data) => data.f),
          t
              .field('pic', b.string.nullable, args: [size])
              .resolve((data, args, context, info) => data.pic(args.get(size))),
          t.field('deep', deepDataType.nullable).pure((data) => data.deep),
          t
              .field('promise', dataType.nullable)
              .resolve((data, args, context, info) => data.promise),
        ],
      );
      final schema = b.build(query: dataType);

      final result = await port.json(
        schema,
        r'''
      query ($size: Int) {
        a,
        b,
        x: c
        ...c
        f
        ...on DataType {
          pic(size: $size)
          promise {
            a
          }
        }
        deep {
          a
          b
          c
          deeper {
            a
            b
          }
        }
      }

      fragment c on DataType {
        d
        e
      }
    ''',
        variables: JsonObject({'size': JsonNumber(100)}),
        options: ExecutionOptions(maskErrors: false, rootValue: _Data()),
      );

      expect(
        result,
        equals({
          'data': {
            'a': 'Apple',
            'b': 'Banana',
            'x': 'Cookie',
            'd': 'Donut',
            'e': 'Egg',
            'f': 'Fish',
            'pic': 'Pic of size: 100',
            'promise': {'a': 'Apple'},
            'deep': {
              'a': 'Already Been Done',
              'b': 'Boring',
              'c': ['Contrived', null, 'Confusing'],
              'deeper': [
                {'a': 'Apple', 'b': 'Banana'},
                null,
                {'a': 'Apple', 'b': 'Banana'},
              ],
            },
          },
        }),
      );
    });

    test('merges parallel fragments', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> type;
      type = b.object<Object?>(
        'Type',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((_) => 'Apple'),
          t.field('b', b.string.nullable).pure((_) => 'Banana'),
          t.field('c', b.string.nullable).pure((_) => 'Cherry'),
          t.field('deep', type.nullable).pure((_) => const Object()),
        ],
      );
      final schema = b.build(query: type);

      final result = port.run(schema, '''
      { a, ...FragOne, ...FragTwo }

      fragment FragOne on Type {
        b
        deep { b, deeper: deep { b } }
      }

      fragment FragTwo on Type {
        c
        deep { c, deeper: deep { c } }
      }
    ''');
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {
            'a': 'Apple',
            'b': 'Banana',
            'c': 'Cherry',
            'deep': {
              'b': 'Banana',
              'c': 'Cherry',
              'deeper': {'b': 'Banana', 'c': 'Cherry'},
            },
          },
        }),
      );
    });

    test('provides info about current execution state', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final completer = Completer<String?>();
      FieldInfo? resolvedInfo;
      final testType = b.object<Object?>(
        'Test',
        fields: (t) => [
          t.field('test', b.string.nullable).resolve((
            value,
            args,
            context,
            info,
          ) {
            resolvedInfo = info;
            return completer.future;
          }),
        ],
      );
      final schema = b.build(query: testType);
      const rootValue = <String, Object?>{'root': 'val'};

      final result = port.run(
        schema,
        r'query ($var: String) { result: test }',
        variables: JsonObject({'var': const JsonString('abc')}),
        options: const ExecutionOptions(
          maskErrors: false,
          rootValue: rootValue,
        ),
      );

      final info = resolvedInfo!;
      expect(info.fieldName, 'test');
      expect(const Printer().print(info.returnType), 'String');
      expect(info.parentType.name, 'Test');
      expect(info.path.toString(), 'result');
      expect(info.schema, same(schema.schema));
      expect(info.rootValue, same(rootValue));
      expect(info.operation.operation, OperationType.query);
      expect(info.fieldNodes.single.alias?.value, 'result');
      expect(info.variables, JsonObject({'var': const JsonString('abc')}));

      completer.complete('done');
      await result;
    });

    test('populates path correctly with complex types', () {
      final b = ExecutableSchemaBuilder<Object?>();
      String? path;
      final someObject = b.object<Object?>(
        'SomeObject',
        fields: (t) => [
          t.field('test', b.string.nullable).resolve((
            value,
            args,
            context,
            info,
          ) {
            path = info.path.toString();
            return null;
          }),
        ],
      );
      final someUnion = b.union<Object?>(
        'SomeUnion',
        members: [someObject],
        resolveType: (_) => someObject,
      );
      final schema = b.build(
        query: b.object<Object?>(
          'SomeQuery',
          fields: (t) => [
            t.field('test', b.list(someUnion)).pure((_) => const [Object()]),
          ],
        ),
      );

      port.run(schema, '''
      query {
        l1: test {
          ... on SomeObject {
            l2: test
          }
        }
      }
    ''');

      expect(path, 'l1.0.l2');
    });

    test('threads root value context correctly', () {
      final b = ExecutableSchemaBuilder<Object?>();
      Object? resolvedRootValue;
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('a', b.string.nullable).pure((rootValue) {
              resolvedRootValue = rootValue;
              return null;
            }),
          ],
        ),
      );
      const rootValue = <String, Object?>{'contextThing': 'thing'};

      port.run(
        schema,
        'query Example { a }',
        options: const ExecutionOptions(rootValue: rootValue),
      );

      expect(resolvedRootValue, same(rootValue));
    });

    test('correctly threads arguments', () {
      final b = ExecutableSchemaBuilder<Object?>();
      final numArg = Arg('numArg', b.int.nullable);
      final stringArg = Arg('stringArg', b.string.nullable);
      (int?, String?)? resolvedArgs;
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('b', b.string.nullable, args: [numArg, stringArg]).resolve((
              _,
              args,
              context,
              info,
            ) {
              resolvedArgs = (args.get(numArg), args.get(stringArg));
              return null;
            }),
          ],
        ),
      );

      port.run(schema, '''
      query Example {
        b(numArg: 123, stringArg: "foo")
      }
    ''');

      expect(resolvedArgs, (123, 'foo'));
    });
  });
}
