import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/cost_fixture.dart';
import '../server/support/hostile_fixture.dart';
import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();
  final hostile = HostileFixture();
  final costs = CostFixture();

  const batching = HttpOptions(batching: BatchPolicy());

  setUp(() {
    hostile.built = 0;
    hostile.resolved = 0;
  });

  Future<List<Object?>> slots(HttpResponseData response) async =>
      (await http.json(response))! as List<Object?>;

  String? slotCode(Object? slot) {
    final errors = (slot! as Map<String, Object?>)['errors'];
    if (errors is! List<Object?>) return null;
    final extensions =
        (errors.first! as Map<String, Object?>)['extensions']!
            as Map<String, Object?>;
    return extensions['code'] as String?;
  }

  group('a hostile batch', () {
    test('of 10,000 items is refused before any item is decoded', () async {
      // The items are not requests: decoding one would be a GQL425.
      final response = await http
          .handlerOver(hostile.server(), options: batching)
          .handle(http.post(List.filled(10000, 1)));
      expect((response.status, await http.code(response)), (422, 'GQL429'));
      expect(hostile.built, 0);
      expect(hostile.resolved, 0);
    });

    test('of a maximal size runs every item once, in order', () async {
      final response = await http
          .handlerOver(hostile.server(), options: batching)
          .handle(http.post(List.filled(10, {'query': '{ hello }'})));
      expect(response.status, 200);
      expect((await slots(response)).length, 10);
      expect(hostile.built, 10);
      expect(hostile.resolved, 10);
    });

    test('with a malformed last item runs nothing', () async {
      final response = await http
          .handlerOver(hostile.server(), options: batching)
          .handle(
            http.post([
              ...List.filled(9, {'query': '{ hello }'}),
              7,
            ]),
          );
      expect((response.status, await http.code(response)), (422, 'GQL425'));
      expect(hostile.built, 0);
      expect(hostile.resolved, 0);
    });

    test('of items each just under the cost limit runs only the first', () async {
      var built = 0;
      final server = costs.server(10, (_) {
        built++;
        return const Ctx('x');
      });
      // Each item costs 7 alone, under 10, so only the shared budget stops it.
      final item = {'query': '{ items(first: 5) { name } }'};
      final response = await http
          .handlerOver(server, options: batching)
          .handle(http.post(List.filled(8, item)));
      final results = await slots(response);
      expect(response.status, 200);
      expect(slotCode(results.first), isNull);
      expect(results.skip(1).map(slotCode), everyElement('GQL430'));
      expect(built, 1);
    });

    test('of mutations is refused item by item and runs no resolver', () async {
      final response = await http
          .handlerOver(hostile.server(), options: batching)
          .handle(http.post(List.filled(5, {'query': 'mutation { bump }'})));
      expect(
        (await slots(response)).map(slotCode),
        everyElement('GQL431'),
      );
      expect(hostile.built, 0);
      expect(hostile.resolved, 0);
    });
  });
}
