import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = JsonObject({'hello': const JsonString('world')});
  final missing = GraphQLError('PersistedQueryNotFound');

  /// The recommended chain (the Request Policies guide) over [mock].
  GraphQLClient clientOver(
    MockLink mock, {
    required String Function() token,
    Future<String?> Function()? refresh,
  }) => GraphQLClient(
    link: Link.from([
      DedupeLink(),
      RetryLink(
        policy: const RetryPolicy(
          backoff: Backoff(initialDelay: Duration.zero),
        ),
      ),
      AuthLink(token: token, refresh: refresh),
      PersistedQueryLink(),
      mock,
    ]),
  );

  List<String?> sentTexts(MockLink mock) => [
    for (final request in mock.requests) request.body.query,
  ];

  group('the policy chain', () {
    test(
      'retries a network failure, then answers a persisted query miss',
      () async {
        final mock = MockLink()
          ..addFailure(const NetworkFailure(FormatException('down')))
          ..addErrors([missing])
          ..addData(hello);
        final response = await clientOver(
          mock,
          token: () => 'abc',
        ).query(const HelloQuery());
        expect(response, isA<GraphQLData<String>>());
        expect(sentTexts(mock), [
          null,
          null,
          HelloQuery.operationDocument.text,
        ]);
      },
    );

    test('every attempt carries the token', () async {
      final mock = MockLink()
        ..addFailure(const NetworkFailure(FormatException('down')))
        ..addData(hello);
      await clientOver(mock, token: () => 'abc').query(const HelloQuery());
      expect(
        [
          for (final request in mock.requests)
            request.context.entry<RequestHeaders>()?.values['authorization'],
        ],
        ['Bearer abc', 'Bearer abc'],
      );
    });

    test('a 401 after a miss refreshes the token and sends the hash', () async {
      var token = 'old';
      final mock = MockLink()
        ..addErrors([missing])
        ..addFailure(HttpStatusFailure(401))
        ..addData(hello);
      final response = await clientOver(
        mock,
        token: () => token,
        refresh: () async => token = 'new',
      ).query(const HelloQuery());
      expect(response, isA<GraphQLData<String>>());
      expect(mock.requests.last.body.query, isNull);
      expect(
        mock.requests.last.context
            .entry<RequestHeaders>()
            ?.values['authorization'],
        'Bearer new',
      );
    });

    test('identical queries sent together cross the chain once', () async {
      final mock = MockLink()..addData(hello);
      final client = clientOver(mock, token: () => 'abc');
      final responses = await Future.wait([
        client.query(const HelloQuery()),
        client.query(const HelloQuery()),
      ]);
      expect(responses, everyElement(isA<GraphQLData<String>>()));
      expect(mock.requests, hasLength(1));
    });
  });
}
