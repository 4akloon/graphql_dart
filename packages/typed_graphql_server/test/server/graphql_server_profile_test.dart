import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  Ctx failingFactory(RequestInfo info) => throw StateError('secret detail');

  test('a negative cache size is an ArgumentError', () {
    expect(
      () => fixture.server(documentCacheSize: -1),
      throwsArgumentError,
    );
  });

  group('errors of the context factory', () {
    test('a GraphQLException is a request error with its extensions', () async {
      final server = fixture.server(
        contextFactory: (_) => throw GraphQLException(
          'Not signed in',
          extensions: JsonObject({'code': const JsonString('AUTH')}),
        ),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(fixture.json(response), {
        'errors': [
          {
            'message': 'Not signed in',
            'extensions': {'code': 'AUTH'},
          },
        ],
      });
    });

    test(
      'production masks the error and calls the hook with the raw one',
      () async {
        Object? seen;
        final server = fixture.server(
          profile: ServerProfile.production,
          contextFactory: failingFactory,
          onError: (error, stackTrace, reported) {
            seen = error;
            return null;
          },
        );
        final response = await server.handle(fixture.request('{ hello }'));
        expect(
          (response as SingleResponse).outcome,
          ServerOutcome.internalError,
        );
        expect(fixture.codeOf(response), 'GQL330');
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(seen, isA<StateError>());
      },
    );

    test('development shows toString()', () async {
      final server = fixture.server(contextFactory: failingFactory);
      final response = await server.handle(fixture.request('{ hello }'));
      expect(
        fixture.messageOf(response),
        'Bad state: secret detail',
      );
    });

    test('a hook can replace the error', () async {
      final server = fixture.server(
        contextFactory: failingFactory,
        onError: (error, stackTrace, reported) => GraphQLError('replaced'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'replaced');
    });

    test('a hook that throws gives the masked error', () async {
      final server = fixture.server(
        contextFactory: failingFactory,
        onError: (error, stackTrace, reported) => throw StateError('hook'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Unexpected error.');
      expect(fixture.codeOf(response), 'GQL330');
    });

    test('an asynchronous failure is handled too', () async {
      final server = fixture.server(
        contextFactory: (_) async => throw StateError('later'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect((response as SingleResponse).outcome, ServerOutcome.internalError);
    });
  });

  group('the profile reaches the execution', () {
    test('production refuses introspection with GQL338', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ __schema { queryType { name } } }'));
      expect(fixture.json(response)['errors'], isNotNull);
      expect(fixture.codeOf(response), 'GQL338');
    });

    test('production still answers __typename', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ __typename }'));
      expect(fixture.json(response), {
        'data': {'__typename': 'Query'},
      });
    });

    test('development answers introspection', () async {
      final response = await fixture.server().handle(
        fixture.request('{ __schema { queryType { name } } }'),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });

    test('production gives no suggestions', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ helo }'));
      expect(fixture.messageOf(response), isNot(contains('Did you mean')));
    });

    test('development gives suggestions', () async {
      final response = await fixture.server().handle(
        fixture.request('{ helo }'),
      );
      expect(fixture.messageOf(response), contains('Did you mean "hello"'));
    });

    test('the timeout ends a slow query with GQL351', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withTimeout(
          const Duration(milliseconds: 20),
        ),
      );
      final response = await server.handle(fixture.request('{ slow }'));
      expect(fixture.codeOf(response), 'GQL351');
    });

    test('the timeout does not end a subscription', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withTimeout(
          const Duration(milliseconds: 20),
        ),
      );
      final response = await server.handle(
        fixture.request('subscription { ticks }'),
      );
      final results = await (response as StreamResponse).results.toList();
      expect(results.map((result) => result.errors), everyElement(isEmpty));
      expect(results, hasLength(2));
    });

    test('the cancel signal reaches the execution with GQL350', () async {
      final signal = CancelSignal()..cancel();
      final response = await fixture.server().handle(
        fixture.request('{ hello }', cancelSignal: signal),
      );
      expect(fixture.codeOf(response), 'GQL350');
    });
  });

  group('the limits', () {
    test('production refuses a depth-16 query before the context', () async {
      var built = 0;
      final server = fixture.server(
        profile: ServerProfile.production,
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
      );
      final response = await server.handle(
        fixture.request(fixture.nested(16)),
      );
      expect(fixture.codeOf(response), 'GQL232');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(built, 0);
    });

    test('development allows it', () async {
      final response = await fixture.server().handle(
        fixture.request(fixture.nested(16)),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });

    test('maxTokens reaches the parser', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withLimits(
          const ServerLimits(maxTokens: 2),
        ),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), startsWith('GQL0'));
      expect(fixture.messageOf(response), contains('token'));
    });

    test('custom validation rules run beside the limit rules', () async {
      final rule = CountingRule();
      final server = fixture.server(
        profile: ServerProfile.production,
        validationRules: [rule],
      );
      await server.handle(fixture.request(fixture.nested(16)));
      expect(rule.runs, 1);
    });
  });
}
