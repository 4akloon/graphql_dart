import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();

  setUp(() => http.contexts = 0);

  // A schema whose `boom` field fails, so a result holds data and an error.
  GraphQLServer<Ctx> failingServer() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('ok', b.string).pure((_) => 'fine'),
        t
            .field('boom', b.string.nullable)
            .resolve((parent, args, context, info) => throw StateError('x')),
      ],
    );
    return GraphQLServer<Ctx>(
      schema: b.build(query: query),
      contextFactory: (_) => const Ctx('x'),
      profile: ServerProfile.development,
    );
  }

  Future<HttpResponseData> partial(
    HttpOptions options,
    Map<String, String> headers,
  ) => http
      .handlerOver(failingServer(), options: options)
      .handle(http.post({'query': '{ ok boom }'}, headers: headers));

  group('a result with errors', () {
    test('is 294 for graphql-response+json', () async {
      final response = await partial(
        const HttpOptions(),
        HttpFixture.modernClient,
      );
      expect(response.status, 294);
      expect(
        await http.json(response),
        containsPair('data', {
          'ok': 'fine',
          'boom': null,
        }),
      );
    });

    test('is 200 when usesPartialSuccessStatus is off', () async {
      final response = await partial(
        const HttpOptions(usesPartialSuccessStatus: false),
        HttpFixture.modernClient,
      );
      expect(response.status, 200);
    });

    test('is 200 for a legacy client', () async {
      final response = await partial(const HttpOptions(), const {
        'accept': 'application/json',
      });
      expect(response.status, 200);
    });
  });

  group('a request the pipeline refuses', () {
    test('is 400 for a document that does not parse', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello'}, headers: HttpFixture.modernClient),
      );
      expect(response.status, 400);
      expect(await http.code(response), startsWith('GQL0'));
    });

    test('is 422 for a document that does not validate', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ nope }'}, headers: HttpFixture.modernClient),
      );
      expect((response.status, await http.code(response)), (422, 'GQL205'));
    });

    test('is 405 with allow: POST for a mutation over GET', () async {
      final response = await http.handler().handle(
        http.get({'query': 'mutation { bump }'}),
      );
      expect((response.status, await http.code(response)), (405, 'GQL402'));
      expect(response.headers['allow'], 'POST');
    });

    test('is 403 when CSRF prevention blocks a GET', () async {
      final response = await http
          .handler(
            profile: ServerProfile.production,
          )
          .handle(http.get({'query': '{ hello }'}, headers: const {}));
      expect((response.status, await http.code(response)), (403, 'GQL403'));
    });

    test(
      'is 422 for a subscription over POST, with no context built',
      () async {
        final response = await http.handler().handle(
          http.post({'query': 'subscription { ticks }'}),
        );
        expect((response.status, await http.code(response)), (422, 'GQL431'));
        expect(http.contexts, 0);
      },
    );

    test('is 500 when the context factory throws', () async {
      final response = await http
          .handler(
            contextFactory: (_) => throw StateError('no context'),
          )
          .handle(http.post({'query': '{ hello }'}));
      expect((response.status, await http.code(response)), (500, 'GQL330'));
    });
  });

  group('a stream from an extension', () {
    test('is cancelled and answered with 500', () async {
      var isCancelled = false;
      final controller = StreamController<ExecutionResult>(
        onCancel: () => isCancelled = true,
      );
      addTearDown(controller.close);
      final response = await http
          .handler(
            extensions: [StreamingExtension(controller.stream)],
          )
          .handle(http.post({'query': '{ hello }'}));
      expect((response.status, await http.code(response)), (500, 'GQL330'));
      expect(isCancelled, isTrue);
    });

    test('is described when errors are not masked', () async {
      final response = await http
          .handler(
            extensions: const [StreamingExtension(Stream.empty())],
          )
          .handle(http.post({'query': '{ hello }'}));
      expect(
        await http.message(response),
        'Bad state: A stream cannot be sent as JSON.',
      );
    });

    test('is not described when errors are masked', () async {
      final response = await http
          .handler(
            profile: ServerProfile.production,
            extensions: const [StreamingExtension(Stream.empty())],
          )
          .handle(http.post({'query': '{ hello }'}));
      expect(
        await http.message(response),
        isNot(contains('A stream cannot be sent as JSON.')),
      );
    });
  });
}
