import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/cost_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final costs = CostFixture();
  final fixture = ServerFixture();
  var built = 0;

  GraphQLServer<Ctx> serverWith(double? maxCost) => costs.server(maxCost, (_) {
    built++;
    return const Ctx('x');
  });

  // Each of these costs 1 (field) and 6 (type): fine alone under 10, not twice.
  const five = '{ items(first: 5) { name } }';

  Future<ServerResponse> send(
    GraphQLServer<Ctx> server,
    String query,
    CostBudget? budget,
  ) => server.handle(fixture.request(query, costBudget: budget));

  setUp(() => built = 0);

  test(
    'the second request that passes alone but not together is GQL430',
    () async {
      final server = serverWith(10);
      final budget = CostBudget();
      final first = await send(server, five, budget);
      final second = await send(server, five, budget);
      expect(fixture.json(first)['data'], isNotNull);
      expect(fixture.codeOf(second), 'GQL430');
    },
  );

  test('the GQL430 message names the summed costs', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    final second = await send(server, five, budget);
    expect(
      fixture.messageOf(second),
      'The anonymous operation would bring the field cost of the requests '
      'that share its limit to 2 and their type cost to 12, more than the '
      'maximum of 10.',
    );
  });

  test('a named operation is named in the GQL430 message', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    final second = await send(server, 'query Big $five', budget);
    expect(
      fixture.messageOf(second),
      startsWith('The operation "Big" would bring'),
    );
  });

  test('GQL430 points at the operation and builds no context', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    built = 0;
    final second = await send(server, five, budget);
    final error =
        (fixture.json(second)['errors']! as List<Object?>).first!
            as Map<String, Object?>;
    expect(error['locations'], [
      {'line': 1, 'column': 1},
    ]);
    expect(built, 0);
  });

  test('GQL430 is a request error', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    final second = await send(server, five, budget);
    expect((second as SingleResponse).outcome, ServerOutcome.requestError);
  });

  test('the budget holds only the costs of the charged requests', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    await send(server, five, budget);
    expect(budget.fieldCost, 1);
    expect(budget.typeCost, 6);
  });

  test('a refused request leaves room for a smaller one', () async {
    final server = serverWith(10);
    final budget = CostBudget();
    await send(server, five, budget);
    await send(server, five, budget);
    final small = await send(server, '{ items(first: 2) { name } }', budget);
    expect(fixture.json(small)['data'], isNotNull);
    expect(budget.typeCost, 9);
  });

  test('without a budget both requests pass', () async {
    final server = serverWith(10);
    final first = await send(server, five, null);
    final second = await send(server, five, null);
    expect(fixture.json(first)['data'], isNotNull);
    expect(fixture.json(second)['data'], isNotNull);
  });

  test('a request over the limit alone is still GQL238', () async {
    final budget = CostBudget();
    final response = await send(
      serverWith(10),
      '{ items(first: 10) { name } }',
      budget,
    );
    expect(fixture.codeOf(response), 'GQL238');
  });

  test('a request over the limit alone is not charged', () async {
    final budget = CostBudget();
    await send(serverWith(10), '{ items(first: 10) { name } }', budget);
    expect(budget.fieldCost, 0);
    expect(budget.typeCost, 0);
  });

  test('a server without maxCost leaves the budget empty', () async {
    final budget = CostBudget();
    await send(serverWith(null), five, budget);
    await send(serverWith(null), five, budget);
    expect(budget.fieldCost, 0);
    expect(budget.typeCost, 0);
  });

  test('a new budget starts at zero', () {
    final budget = CostBudget();
    expect(budget.fieldCost, 0);
    expect(budget.typeCost, 0);
  });
}
