import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

final class Crate {
  const Crate();
}

final class FailingCodec implements ScalarCodec<String> {
  const FailingCodec(this.failure);

  final Error failure;

  @override
  DecodeResult<String> decode(JsonValue json) => const DecodeFailure('no');

  @override
  JsonValue encode(String value) => throw failure;
}

final class Counter {
  int calls = 0;
}

final class FailureFixture {
  FailureFixture() {
    final b = ExecutableSchemaBuilder<Counter>();
    final crate = b.object<Crate>(
      'Crate',
      fields: (t) => [t.field('size', b.int).pure((_) => 1)],
      options: ObjectOptions(isTypeOf: (_) => throw StateError('isTypeOf')),
    );
    final explicit = b.union<Object>(
      'Explicit',
      members: [crate],
      resolveType: (_) => crate,
    );
    final byDefault = b.union<Object>('Default', members: [crate]);
    final argument = b.scalar<String>(
      'ArgumentFailure',
      FailingCodec(ArgumentError('cannot show it')),
    );
    final emptyArgument = b.scalar<String>(
      'EmptyArgumentFailure',
      FailingCodec(ArgumentError()),
    );
    final range = b.scalar<String>(
      'RangeFailure',
      FailingCodec(RangeError('secret range')),
    );
    final state = b.scalar<String>(
      'StateFailure',
      FailingCodec(StateError('secret state')),
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('explicit', explicit.nullable).pure((_) => const Crate()),
        t
            .field('explicitLater', explicit.nullable)
            .resolve((parent, args, context, info) async => const Crate()),
        t.field('byDefault', byDefault.nullable).pure((_) => const Crate()),
        t
            .field('lazyLater', b.list(b.int).nullable)
            .resolve((parent, args, context, info) async => _lazy()),
        t.field('argument', argument.nullable).pure((_) => 'x'),
        t.field('emptyArgument', emptyArgument.nullable).pure((_) => 'x'),
        t.field('range', range.nullable).pure((_) => 'x'),
        t.field('state', state.nullable).pure((_) => 'x'),
        t.field('slowFail', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          throw StateError('slow');
        }),
        t.field('quickFail', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          throw StateError('quick');
        }),
        t.field('self', query).pure((_) => const Object()),
        t.field('counted', b.string).resolve((parent, args, context, info) {
          context.calls++;
          return 'counted';
        }),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Counter> built;

  static Iterable<int> _lazy() sync* {
    yield 1;
    throw StateError('lazy');
  }

  Future<Map<String, Object?>> json(
    String text, {
    Counter? context,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: context ?? Counter(),
      options: options,
    );
    return payload.toJson().toJson();
  }
}

void main() {
  final f = FailureFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  String messageOf(Object? error) =>
      (error! as Map<String, Object?>)['message']! as String;

  List<Object?> pathsOf(Map<String, Object?> json) => [
    for (final error in errorsOf(json))
      (error! as Map<String, Object?>)['path'],
  ];

  group('a throw during completion', () {
    test('isTypeOf after an explicit resolveType is a field error', () async {
      final json = await f.json('{ explicit { size } }');
      expect(json['data'], {'explicit': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('isTypeOf after an async resolver is a field error', () async {
      final json = await f.json('{ explicitLater { size } }');
      expect(json['data'], {'explicitLater': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('isTypeOf in the default resolution is a field error', () async {
      final json = await f.json('{ byDefault { size } }');
      expect(json['data'], {'byDefault': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('a throwing iterable behind a future is a field error', () async {
      final json = await f.json('{ lazyLater }');
      expect(json['data'], {'lazyLater': null});
      expect(errorsOf(json), hasLength(1));
    });

    test('the message is masked', () async {
      final json = await f.json('{ explicit { size } }');
      expect(messageOf(errorsOf(json).single), 'Unexpected error.');
    });
  });

  group('a codec failure', () {
    test('an ArgumentError is GQL332 with its message', () async {
      final json = await f.json('{ argument }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL332');
      expect(messageOf(error), 'cannot show it');
    });

    test('an ArgumentError without a message never prints null', () async {
      final json = await f.json('{ emptyArgument }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL332');
      expect(messageOf(error), isNot(contains('null')));
    });

    test('a RangeError is an unexpected, masked error', () async {
      final json = await f.json('{ range }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL330');
      expect(messageOf(error), 'Unexpected error.');
    });

    test('another error is an unexpected, masked error', () async {
      final json = await f.json('{ state }');
      expect(messageOf(errorsOf(json).single), 'Unexpected error.');
    });

    test('a RangeError reaches onError', () async {
      Object? seen;
      await f.json(
        '{ range }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            seen = error;
            return null;
          },
        ),
      );
      expect(seen, isA<RangeError>());
    });
  });

  group('error order', () {
    test('errors follow the document, not the completion', () async {
      final json = await f.json('{ slowFail quickFail }');
      expect(pathsOf(json), [
        ['slowFail'],
        ['quickFail'],
      ]);
    });

    test('a later field that finishes first is listed last', () async {
      final json = await f.json('{ quickFail slowFail }');
      expect(pathsOf(json), [
        ['quickFail'],
        ['slowFail'],
      ]);
    });
  });

  group('depth', () {
    test('a too-deep field runs no resolver', () async {
      final counter = Counter();
      final json = await f.json(
        '{ self { self { counted } } }',
        context: counter,
        options: const ExecutionOptions(maxDepth: 2),
      );
      expect(counter.calls, 0);
      expect(codeOf(errorsOf(json).single), 'GQL336');
    });

    test('a field within the depth runs its resolver', () async {
      final counter = Counter();
      await f.json(
        '{ self { counted } }',
        context: counter,
        options: const ExecutionOptions(maxDepth: 2),
      );
      expect(counter.calls, 1);
    });
  });
}
