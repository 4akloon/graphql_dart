import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/cost_fixture.dart';
import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();
  final costs = CostFixture();

  const batching = HttpOptions(batching: BatchPolicy());

  setUp(() => http.contexts = 0);

  Future<List<Object?>> slots(HttpResponseData response) async =>
      (await http.json(response))! as List<Object?>;

  String? slotCode(Object? slot) {
    final errors = (slot! as Map<String, Object?>)['errors']! as List<Object?>;
    final extensions =
        (errors.first! as Map<String, Object?>)['extensions']!
            as Map<String, Object?>;
    return extensions['code'] as String?;
  }

  group('a batch', () {
    test('is refused when batching is off', () async {
      final response = await http.handler().handle(
        http.post([
          {'query': '{ hello }'},
        ]),
      );
      expect((response.status, await http.code(response)), (422, 'GQL428'));
    });

    test('answers the items in order', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': '{ greet(name: "x") }'},
            ]),
          );
      expect(response.status, 200);
      expect(await slots(response), [
        {
          'data': {'hello': 'world'},
        },
        {
          'data': {'greet': 'x'},
        },
      ]);
    });

    test(
      'is 200 with the negotiated media type whatever the items hold',
      () async {
        final response = await http
            .handler(options: batching)
            .handle(
              http.post([
                {'query': '{ nope }'},
              ], headers: HttpFixture.modernClient),
            );
        expect(response.status, 200);
        expect(
          response.headers['content-type'],
          'application/graphql-response+json; charset=utf-8',
        );
        expect(slotCode((await slots(response)).single), 'GQL205');
      },
    );

    test('builds a context for each item', () async {
      await http
          .handler(options: batching)
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': '{ hello }'},
            ]),
          );
      expect(http.contexts, 2);
    });

    test('runs its items one after the other', () async {
      final log = <String>[];
      await http
          .handler(
            options: batching,
            contextFactory: (_) async {
              log.add('start');
              await Future<void>.delayed(Duration.zero);
              log.add('end');
              return const Ctx('x');
            },
          )
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': '{ hello }'},
            ]),
          );
      expect(log, ['start', 'end', 'start', 'end']);
    });
  });

  group('the size of a batch', () {
    test('may not be empty', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post(<Object?>[]),
          );
      expect((response.status, await http.code(response)), (422, 'GQL429'));
      expect(
        await http.message(response),
        'A batch must hold between 1 and 10 requests.',
      );
    });

    test('may not pass maxRequests', () async {
      final response = await http
          .handler(
            options: const HttpOptions(
              batching: BatchPolicy(maxRequests: 2),
            ),
          )
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': '{ hello }'},
              {'query': '{ hello }'},
            ]),
          );
      expect((response.status, await http.code(response)), (422, 'GQL429'));
      expect(http.contexts, 0);
    });
  });

  group('a malformed item', () {
    test('refuses the whole batch, naming the index', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': 1},
            ]),
          );
      expect((response.status, await http.code(response)), (422, 'GQL425'));
      expect(
        await http.message(response),
        'The request at index 1 is malformed: expected a string at query',
      );
      expect(http.contexts, 0);
    });

    test('refuses an item that is not an object', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post([1]),
          );
      expect(
        await http.message(response),
        'The request at index 0 is malformed: expected an object',
      );
    });
  });

  group('the operation types of an item', () {
    final mutationThenQuery = [
      {'query': 'mutation { bump }'},
      {'query': '{ hello }'},
    ];

    test('refuse a mutation in its own slot and still run the query', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post(mutationThenQuery),
          );
      final results = await slots(response);
      expect(slotCode(results.first), 'GQL431');
      expect(results.last, {
        'data': {'hello': 'world'},
      });
      expect(http.contexts, 1);
    });

    test('allow a mutation when the policy does', () async {
      final response = await http
          .handler(
            options: const HttpOptions(
              batching: BatchPolicy(allowsMutations: true),
            ),
          )
          .handle(http.post(mutationThenQuery));
      expect(await slots(response), [
        {
          'data': {'bump': 'bumped'},
        },
        {
          'data': {'hello': 'world'},
        },
      ]);
    });

    test('refuse a subscription in its slot', () async {
      final response = await http
          .handler(options: batching)
          .handle(
            http.post([
              {'query': 'subscription { ticks }'},
            ]),
          );
      expect(slotCode((await slots(response)).single), 'GQL431');
      expect(http.contexts, 0);
    });
  });

  group('the cost of a batch', () {
    // Each item costs 1 (field) and 6 (type): fine alone under 10, not twice.
    final item = {'query': '{ items(first: 5) { name } }'};

    test('is shared: the second item is GQL430', () async {
      var built = 0;
      final server = costs.server(10, (_) {
        built++;
        return const Ctx('x');
      });
      final response = await http
          .handlerOver(server, options: batching)
          .handle(http.post([item, item]));
      final results = await slots(response);
      expect(
        results.first,
        isA<Map<String, Object?>>().having(
          (slot) => slot['data'],
          'data',
          isNotNull,
        ),
      );
      expect(slotCode(results.last), 'GQL430');
      expect(built, 1);
    });

    test('is not charged for an item that was refused', () async {
      final server = costs.server(10, (_) => const Ctx('x'));
      final response = await http
          .handlerOver(server, options: batching)
          .handle(
            http.post([
              item,
              item,
              {'query': '{ items(first: 1) { name } }'},
            ]),
          );
      final results = await slots(response);
      expect(
        [
          for (final slot in results)
            (slot! as Map<String, Object?>).keys.first,
        ],
        ['data', 'errors', 'data'],
      );
    });
  });

  group('a stream from an extension', () {
    test('is cancelled and reported in its slot', () async {
      var isCancelled = false;
      final controller = StreamController<ExecutionResult>(
        onCancel: () => isCancelled = true,
      );
      addTearDown(controller.close);
      final response = await http
          .handler(
            options: batching,
            extensions: [StreamingExtension(controller.stream)],
          )
          .handle(
            http.post([
              {'query': '{ hello }'},
            ]),
          );
      expect(slotCode((await slots(response)).single), 'GQL330');
      expect(isCancelled, isTrue);
    });
  });

  group('the constructor', () {
    test('rejects a maxRequests below one', () {
      expect(
        () => http.handler(
          options: const HttpOptions(batching: BatchPolicy(maxRequests: 0)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxRequests',
          ),
        ),
      );
    });
  });
}
