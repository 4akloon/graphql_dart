import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('a query', () {
    test('runs and returns its data as executed', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.executed);
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('receives its variables', () async {
      final response = await fixture.server().handle(
        fixture.request(
          r'query Q($n: String!) { greet(name: $n) }',
          variables: JsonObject({'n': const JsonString('Ada')}),
        ),
      );
      expect(fixture.json(response), {
        'data': {'greet': 'Ada'},
      });
    });

    test('runs the operation named by operationName', () async {
      final response = await fixture.server().handle(
        fixture.request(
          'query A { hello } query B { tag }',
          operationName: 'B',
        ),
      );
      expect(fixture.json(response), {
        'data': {'tag': 'default'},
      });
    });

    test('reads the context the factory built', () async {
      final server = fixture.server(contextFactory: (_) => const Ctx('mine'));
      final response = await server.handle(fixture.request('{ tag }'));
      expect(fixture.json(response), {
        'data': {'tag': 'mine'},
      });
    });

    test('is allowed with GET', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', method: 'get'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.executed);
    });
  });

  group('a request without a document', () {
    test('has no query: GQL400', () async {
      final response = await fixture.server().handle(fixture.request(null));
      expect(fixture.codeOf(response), 'GQL400');
      expect(fixture.messageOf(response), 'Must provide query string.');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('has an empty query: GQL400', () async {
      final response = await fixture.server().handle(fixture.request(''));
      expect(fixture.codeOf(response), 'GQL400');
    });
  });

  group('the document length', () {
    const small = ServerProfile(
      introspection: .enabled,
      includesSuggestions: true,
      maskErrors: false,
      csrfPrevention: null,
      limits: ServerLimits(maxDocumentLength: 10),
    );

    test('over the maximum is GQL401', () async {
      final server = fixture.server(profile: small);
      final response = await server.handle(fixture.request('{ hello  }  '));
      expect(fixture.codeOf(response), 'GQL401');
      expect(
        fixture.messageOf(response),
        'The document is longer than the maximum of 10 characters.',
      );
    });

    test('over the maximum never reaches validation', () async {
      final rule = CountingRule();
      final server = fixture.server(
        profile: small,
        validationRules: [rule],
      );
      await server.handle(fixture.request('{ hello  }  '));
      expect(rule.runs, 0);
    });

    test('at the maximum is served', () async {
      final response = await fixture
          .server(
            profile: small,
          )
          .handle(fixture.request('{ hello } '));
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  group('a rejected document', () {
    test('is a request error with its errors', () async {
      final response = await fixture.server().handle(
        fixture.request('{ nothing }'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(fixture.codeOf(response), startsWith('GQL2'));
    });

    test('is not validated again for the same text', () async {
      final rule = CountingRule();
      final server = fixture.server(validationRules: [rule]);
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(rule.runs, 1);
    });

    test(
      'is validated again when its text is over documentCacheMaxLength',
      () async {
        final rule = CountingRule();
        const text = '{ hello }';
        final server = fixture.server(
          validationRules: [rule],
          documentCacheMaxLength: text.length - 1,
        );
        await server.handle(fixture.request(text));
        await server.handle(fixture.request(text));
        expect(rule.runs, 2);
      },
    );

    test('is kept when its text fits documentCacheMaxLength', () async {
      final rule = CountingRule();
      const text = '{ hello }';
      final server = fixture.server(
        validationRules: [rule],
        documentCacheMaxLength: text.length,
      );
      await server.handle(fixture.request(text));
      await server.handle(fixture.request(text));
      expect(rule.runs, 1);
    });

    test('is validated again with the cache off', () async {
      final rule = CountingRule();
      final server = fixture.server(
        validationRules: [rule],
        documentCacheSize: 0,
      );
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(rule.runs, 2);
    });
  });

  group('the operation', () {
    test('a mutation with GET is GQL402 with an allow header', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }', method: 'GET'),
      );
      expect(
        (response as SingleResponse).outcome,
        ServerOutcome.methodNotAllowed,
      );
      expect(fixture.codeOf(response), 'GQL402');
      expect(response.headers, {'allow': 'POST'});
    });

    test('a mutation with HEAD is refused like GET', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }', method: 'HEAD'),
      );
      expect(
        (response as SingleResponse).outcome,
        ServerOutcome.methodNotAllowed,
      );
      expect(fixture.codeOf(response), 'GQL402');
      expect(response.headers, {'allow': 'POST'});
    });

    test('a mutation with get in lower case is refused too', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }', method: 'get'),
      );
      expect(fixture.codeOf(response), 'GQL402');
    });

    for (final method in ['PUT', 'DELETE', 'PATCH', 'OPTIONS', '', 'put']) {
      test('a mutation with "$method" is refused', () async {
        final response = await fixture.server().handle(
          fixture.request('mutation { bump }', method: method),
        );
        expect(fixture.codeOf(response), 'GQL402');
        expect(response.headers, {'allow': 'POST'});
      });
    }

    test('a query with GET runs', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', method: 'GET'),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a mutation with POST runs', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }'),
      );
      expect(fixture.json(response), {
        'data': {'bump': 'bumped'},
      });
    });

    test('the mutation of an operation name decides, not the first', () async {
      final response = await fixture.server().handle(
        fixture.request(
          'mutation M { bump } query Q { hello }',
          method: 'GET',
          operationName: 'Q',
        ),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('an unknown operation name is reported by the executor', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', operationName: 'Nope'),
      );
      expect(fixture.codeOf(response), 'GQL320');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('several operations without a name are GQL321', () async {
      final response = await fixture.server().handle(
        fixture.request('query A { hello } query B { hello }'),
      );
      expect(fixture.codeOf(response), 'GQL321');
    });
    test('a mutation named next to an anonymous query is GQL402', () async {
      // The lone-anonymous rule would refuse this document first.
      final response = await fixture
          .server(validationRules: [])
          .handle(
            fixture.request(
              '{ hello } mutation M { bump }',
              method: 'GET',
              operationName: 'M',
            ),
          );
      expect(fixture.codeOf(response), 'GQL402');
    });

    test(
      'of a query and a mutation sharing a name, the last decides',
      () async {
        // Without UniqueOperationNames the executor would run the mutation.
        final response = await fixture
            .server(validationRules: [])
            .handle(
              fixture.request(
                'query Q { hello } mutation Q { bump }',
                method: 'GET',
                operationName: 'Q',
              ),
            );
        expect(fixture.codeOf(response), 'GQL402');
      },
    );

    test('an empty operation name names no operation: GQL320', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', operationName: ''),
      );
      expect(fixture.codeOf(response), 'GQL320');
    });
  });

  group('the context factory', () {
    int built = 0;

    GraphQLServer<Ctx> counting() => fixture.server(
      contextFactory: (_) {
        built++;
        return const Ctx('x');
      },
    );

    setUp(() => built = 0);

    test('is not called for a mutation over GET', () async {
      await counting().handle(
        fixture.request('mutation { bump }', method: 'GET'),
      );
      expect(built, 0);
    });

    test('is not called for an invalid document', () async {
      await counting().handle(fixture.request('{ nothing }'));
      expect(built, 0);
    });

    test('is not called without a query', () async {
      await counting().handle(fixture.request(null));
      expect(built, 0);
    });

    test('throwing synchronously gives GQL330', () async {
      final server = fixture.server(
        contextFactory: (_) {
          throw StateError('boom');
        },
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL330');
      expect(
        (response as SingleResponse).outcome,
        ServerOutcome.internalError,
      );
    });

    test('throwing an object whose toString throws still answers', () async {
      final server = fixture.server(
        contextFactory: (_) {
          throw const UnprintableError();
        },
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL330');
      expect(fixture.messageOf(response), 'Unexpected error.');
    });
  });

  group('a subscription', () {
    test('starts as a stream, also with GET', () async {
      final response = await fixture.server().handle(
        fixture.request('subscription { ticks }', method: 'GET'),
      );
      expect(response, isA<StreamResponse>());
      expect(response.outcome, ServerOutcome.executed);
      final results = await (response as StreamResponse).results.toList();
      expect(
        [for (final result in results) result.toJson().toJson()['data']],
        [
          {'ticks': 'tick 1'},
          {'ticks': 'tick 2'},
        ],
      );
    });

    test('rejected by the executor is a request error', () async {
      final response = await fixture.server().handle(
        fixture.request('subscription A { ticks } subscription B { ticks }'),
      );
      expect(fixture.codeOf(response), 'GQL321');
    });
  });
}
