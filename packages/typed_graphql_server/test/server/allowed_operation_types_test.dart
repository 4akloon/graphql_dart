import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  var built = 0;

  GraphQLServer<Ctx> counting({
    ServerProfile profile = ServerProfile.development,
  }) => fixture.server(
    profile: profile,
    contextFactory: (_) {
      built++;
      return const Ctx('x');
    },
  );

  setUp(() => built = 0);

  test(
    'a subscription is refused with GQL431 when it is not allowed',
    () async {
      final response = await counting().handle(
        fixture.request(
          'subscription { ticks }',
          allowedOperationTypes: {OperationType.query},
        ),
      );
      expect(fixture.codeOf(response), 'GQL431');
      expect(
        fixture.messageOf(response),
        'A subscription is not allowed in this request.',
      );
    },
  );

  test('a refused subscription is a request error', () async {
    final response = await counting().handle(
      fixture.request(
        'subscription { ticks }',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect((response as SingleResponse).outcome, ServerOutcome.requestError);
  });

  test('a refused subscription builds no context', () async {
    await counting().handle(
      fixture.request(
        'subscription { ticks }',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(built, 0);
  });

  test('a mutation is refused when only queries are allowed', () async {
    final response = await counting().handle(
      fixture.request(
        'mutation { bump }',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(fixture.codeOf(response), 'GQL431');
    expect(
      fixture.messageOf(response),
      'A mutation is not allowed in this request.',
    );
    expect(built, 0);
  });

  test('a query is refused when it is not allowed', () async {
    final response = await counting().handle(
      fixture.request(
        '{ hello }',
        allowedOperationTypes: {OperationType.mutation},
      ),
    );
    expect(fixture.codeOf(response), 'GQL431');
    expect(
      fixture.messageOf(response),
      'A query is not allowed in this request.',
    );
  });

  test('an allowed type runs', () async {
    final response = await counting().handle(
      fixture.request(
        '{ hello }',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(fixture.json(response)['data'], {'hello': 'world'});
  });

  test('the default allows a subscription', () async {
    final response = await counting().handle(
      fixture.request('subscription { ticks }'),
    );
    expect(response, isA<StreamResponse>());
    await (response as StreamResponse).results.drain<void>();
  });

  test('the type of the selected operation decides', () async {
    final response = await counting().handle(
      fixture.request(
        'query A { hello } mutation B { bump }',
        operationName: 'A',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(fixture.json(response)['data'], {'hello': 'world'});
  });

  test('a GET mutation keeps GQL402 when mutations are not allowed', () async {
    final response = await counting().handle(
      fixture.request(
        'mutation { bump }',
        method: 'GET',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(fixture.codeOf(response), 'GQL402');
    expect(
      (response as SingleResponse).outcome,
      ServerOutcome.methodNotAllowed,
    );
  });

  test('no operation selected is left to the executor', () async {
    final response = await counting().handle(
      fixture.request(
        '{ hello }',
        operationName: 'Missing',
        allowedOperationTypes: {OperationType.query},
      ),
    );
    expect(fixture.codeOf(response), isNot('GQL431'));
  });

  test('the server exposes the profile it was built with', () {
    const profile = ServerProfile.production;
    expect(counting(profile: profile).profile, same(profile));
  });
}
