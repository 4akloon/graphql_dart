import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

// A forgotten profile must not expose a server (spec section 17 item 1):
// every test here builds the server without `profile:`.
void main() {
  final fixture = ServerFixture();
  final builder = ExecutableSchemaBuilder<Ctx>();
  final query = builder.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', builder.string).pure((_) => 'world'),
      t
          .field('boom', builder.string)
          .resolve((parent, args, context, info) => throw StateError('secret')),
    ],
  );
  final server = GraphQLServer<Ctx>(
    schema: builder.build(query: query),
    contextFactory: (_) => const Ctx('default'),
  );

  test('masks an unexpected resolver error', () async {
    final response = await server.handle(fixture.request('{ boom }'));
    final body = fixture.json(response).toString();
    expect(body, contains('Unexpected error.'));
    expect(body, isNot(contains('secret')));
  });

  test('gives no suggestions', () async {
    final response = await server.handle(fixture.request('{ helo }'));
    expect(fixture.messageOf(response), isNot(contains('Did you mean')));
  });

  test('refuses introspection with GQL338', () async {
    final response = await server.handle(
      fixture.request('{ __schema { queryType { name } } }'),
    );
    expect(fixture.json(response)['data'], isNull);
    expect(fixture.json(response).toString(), contains('GQL338'));
  });

  test('refuses a GET without a preflight header with GQL403', () async {
    final response = await server.handle(
      fixture.request('{ hello }', method: 'GET', headers: const {}),
    );
    expect(fixture.codeOf(response), 'GQL403');
  });

  test('applies the production limits', () async {
    final aliases = [for (var i = 0; i < 16; i++) 'a$i: hello'].join(' ');
    final response = await server.handle(fixture.request('{ $aliases }'));
    expect(fixture.codeOf(response), 'GQL233');
  });
}
