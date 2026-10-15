import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/recording_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('in production', () {
    test('a GET without content type or preflight header is GQL403', () async {
      var built = 0;
      final server = fixture.server(
        profile: ServerProfile.production,
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
      );
      final response = await server.handle(
        fixture.request('{ hello }', method: 'GET', headers: const {}),
      );
      expect(fixture.codeOf(response), 'GQL403');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(built, 0);
    });

    test('a POST with application/json passes', () async {
      final response = await fixture
          .server(profile: ServerProfile.production)
          .handle(fixture.request('{ hello }'));
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a GET with a preflight header passes', () async {
      final response = await fixture
          .server(profile: ServerProfile.production)
          .handle(
            fixture.request(
              '{ hello }',
              method: 'GET',
              headers: const {'apollo-require-preflight': 'true'},
            ),
          );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('withCsrfPrevention(null) turns it off', () async {
      final server = fixture.server(
        profile: ServerProfile.production.withCsrfPrevention(null),
      );
      final response = await server.handle(
        fixture.request('{ hello }', method: 'GET', headers: const {}),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  test('the user extensions see the refusal', () async {
    final log = <String>[];
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [RecordingExtension('a', log)],
    );
    final response = await server.handle(
      fixture.request('{ hello }', method: 'GET', headers: const {}),
    );
    expect(fixture.codeOf(response), 'GQL403');
    expect(log, ['a:request', '/a:request']);
  });

  group('a user extension that rewrites the request', () {
    ServerRequest withHeaders(
      ServerRequest request,
      Map<String, String> headers,
    ) => ServerRequest(
      params: request.params,
      info: RequestInfo(
        method: request.info.method,
        uri: request.info.uri,
        headers: headers,
      ),
    );

    test('adding the preflight header lets a blocked request pass', () async {
      final server = fixture.server(
        profile: ServerProfile.production,
        extensions: [
          HookExtension(
            request: (request, next) => next(
              withHeaders(request, {'graphql-require-preflight': '1'}),
            ),
          ),
        ],
      );
      final response = await server.handle(
        fixture.request('{ hello }', method: 'GET', headers: const {}),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('removing the content type is GQL403', () async {
      final server = fixture.server(
        profile: ServerProfile.production,
        extensions: [
          HookExtension(
            request: (request, next) => next(withHeaders(request, const {})),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL403');
    });
  });
}
