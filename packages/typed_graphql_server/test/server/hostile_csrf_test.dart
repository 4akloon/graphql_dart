import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();
  final server = hostile.server();

  setUp(() {
    hostile
      ..built = 0
      ..resolved = 0;
  });

  Future<ServerResponse> send(
    Map<String, String> headers, {
    String method = 'POST',
    String text = '{ hello }',
  }) => server.handle(fixture.request(text, method: method, headers: headers));

  void expectBlocked(ServerResponse response) {
    expect(fixture.codeOf(response), 'GQL403');
    expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    expect(hostile.built, 0, reason: 'no context');
    expect(hostile.resolved, 0, reason: 'no resolver');
  }

  group('a request a browser can send cross-site is GQL403', () {
    test('a GET without headers', () async {
      expectBlocked(await send(const {}, method: 'GET'));
    });

    for (final type in [
      'application/x-www-form-urlencoded',
      'multipart/form-data',
      'text/plain',
    ]) {
      test('a POST with $type', () async {
        expectBlocked(await send({'content-type': type}));
      });
    }

    test('a POST with odd case and a parameter', () async {
      expectBlocked(await send({'Content-Type': 'Text/Plain; charset=utf-8'}));
    });

    test('a POST with an unparsable type', () async {
      expectBlocked(await send({'content-type': 'json'}));
    });

    test('a POST with joined headers whose first value is simple', () async {
      expectBlocked(
        await send({'content-type': 'text/plain, application/json'}),
      );
    });

    test('an empty preflight header without a content type', () async {
      expectBlocked(await send({'graphql-require-preflight': ''}));
    });

    test('a whitespace preflight header without a content type', () async {
      expectBlocked(await send({'apollo-require-preflight': '  '}));
    });
  });

  group('a request a browser cannot send cross-site passes', () {
    test('a POST with application/json', () async {
      final response = await send({'content-type': 'application/json'});
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a POST with application/json and a charset', () async {
      final response = await send({
        'content-type': 'application/json; charset=utf-8',
      });
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a GET with a non-empty preflight header', () async {
      final response = await send({
        'graphql-require-preflight': '1',
      }, method: 'GET');
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  test('a mutation in a GET with a preflight header is still GQL402', () async {
    final response = await send(
      {'graphql-require-preflight': '1'},
      method: 'GET',
      text: 'mutation { bump }',
    );
    expect(fixture.codeOf(response), 'GQL402');
    expect(
      (response as SingleResponse).outcome,
      ServerOutcome.methodNotAllowed,
    );
  });
}
