import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'authorization_fixture.dart';

void main() {
  late RoleAuthorizer authorizer;
  late List<String> resolved;
  late ExecutableSchema<Caller> built;

  setUp(() {
    authorizer = RoleAuthorizer();
    resolved = [];
    final b = ExecutableSchemaBuilder<Caller>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('ok', b.string).resolve((p, a, c, i) => 'ok')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('tick', b.string)
            .withAuthorization(Authorization.requires(['admin']))
            .subscribeWith<String>(
              (p, a, c, i) => Stream.value('event'),
              (event, a, c, i) {
                resolved.add(event);
                return 'tick';
              },
            ),
      ],
    );
    built = b.build(
      query: query,
      subscription: subscription,
      options: BuildOptions<Caller>(authorizer: authorizer),
    );
  });

  Future<Map<String, Object?>> execute(Set<String> roles) async {
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source('subscription { tick }')).requireDocument();
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, parsed),
      context: Caller(roles),
      options: const ExecutionOptions(rootValue: 'event'),
    );
    return payload.toJson().toJson();
  }

  test('execute on a guarded subscription denies a caller', () async {
    final json = await execute({});
    final error = (json['errors']! as List<Object?>).first! as Map;
    expect((error['extensions']! as Map)['code'], 'GQL352');
    expect(resolved, isEmpty);
  });

  test('execute on a guarded subscription asks the authorizer once', () async {
    final json = await execute({'admin'});
    expect(json, {
      'data': {'tick': 'tick'},
    });
    expect(authorizer.calls, ['Subscription.tick']);
  });
}
