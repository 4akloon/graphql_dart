import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  test('withContext reaches the resolvers', () async {
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) =>
              next(request.withContext(const Ctx('hook'))),
        ),
      ],
    );
    final response = await server.handle(fixture.request('{ tag }'));
    expect(fixture.json(response)['data'], {'tag': 'hook'});
  });

  test('withOptions takes effect: introspection in production', () async {
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [
        HookExtension(
          execute: (request, next) => next(
            request.withOptions(
              ExecutionOptions(
                source: request.options.source,
                introspection: .enabled,
              ),
            ),
          ),
        ),
      ],
    );
    final response = await server.handle(
      fixture.request('{ __schema { queryType { name } } }'),
    );
    expect(fixture.json(response)['data'], isNotNull);
  });

  test('the options hold the profile settings before any hook', () async {
    ExecutionOptions? seen;
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [
        HookExtension(
          execute: (request, next) {
            seen = request.options;
            return next(request);
          },
        ),
      ],
    );
    await server.handle(fixture.request('{ hello }'));
    expect(seen?.maskErrors, isTrue);
    expect(seen?.source?.body, '{ hello }');
  });

  test('sees the response coming back and may add headers', () async {
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) async =>
              (await next(request)).withHeaders({'X-Trace': '1'}),
        ),
      ],
    );
    final response = await server.handle(fixture.request('{ hello }'));
    expect(response.headers, {'x-trace': '1'});
  });

  test('is not reached by a rejected document', () async {
    var reached = false;
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) {
            reached = true;
            return next(request);
          },
        ),
      ],
    );
    await server.handle(fixture.request('{ nothing }'));
    expect(reached, isFalse);
  });

  group('the timeout the hook sees', () {
    final profile = ServerProfile.production.withTimeout(
      const Duration(seconds: 5),
    );

    Future<Duration?> timeoutSeenFor(String query) async {
      Duration? seen;
      final server = fixture.server(
        profile: profile,
        extensions: [
          HookExtension(
            execute: (request, next) {
              seen = request.options.timeout;
              return next(request);
            },
          ),
        ],
      );
      await server.handle(fixture.request(query));
      return seen;
    }

    test('a query has the profile timeout', () async {
      expect(await timeoutSeenFor('{ hello }'), const Duration(seconds: 5));
    });

    test('a subscription has none', () async {
      expect(await timeoutSeenFor('subscription { ticks }'), isNull);
    });
  });
}
