import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/sse/connect_outcome.dart';
import 'package:typed_graphql_server/src/sse/stream_reservations.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/sse_fixture.dart';

const Duration _timeout = Duration(milliseconds: 20);

void main() {
  StreamReservations reservations({int max = 2}) => StreamReservations(
    SingleConnectionOptions(
      maxReservations: max,
      reservationTimeout: _timeout,
      maxOperationsPerStream: 2,
    ),
    keepAliveInterval: const Duration(hours: 1),
  );

  group('StreamReservations', () {
    test('reserve gives distinct tokens of 32 hex digits', () {
      final store = reservations();
      final tokens = {store.reserve(), store.reserve()};
      expect(tokens, hasLength(2));
      expect(tokens, everyElement(matches(RegExp(r'^[0-9a-f]{32}$'))));
    });

    test('reserve gives null when the maximum is held', () {
      final store = reservations(max: 1);
      expect(store.reserve(), isNotNull);
      expect(store.reserve(), isNull);
    });

    test('connect to an unknown token is a miss', () {
      expect(reservations().connect('nope'), isA<UnknownToken>());
    });

    test('connect twice is an already open miss', () {
      final store = reservations();
      final token = store.reserve()!;
      expect(store.connect(token), isA<Connected>());
      expect(store.connect(token), isA<AlreadyOpen>());
    });

    test(
      'a reservation nobody connects is dropped after the timeout',
      () async {
        final store = reservations(max: 1);
        final token = store.reserve()!;
        await Future<void>.delayed(_timeout * 3);
        expect(store.connect(token), isA<UnknownToken>());
        expect(store.reserve(), isNotNull);
      },
    );

    test('a connected reservation outlives the timeout', () async {
      final store = reservations();
      final token = store.reserve()!;
      final outcome = store.connect(token) as Connected;
      final reader = StreamReader(outcome.stream.response());
      await Future<void>.delayed(_timeout * 3);
      expect(store.connect(token), isA<AlreadyOpen>());
      await reader.cancel();
    });

    test('closing a connected stream drops the reservation', () async {
      final store = reservations();
      final token = store.reserve()!;
      final outcome = store.connect(token) as Connected;
      final reader = StreamReader(outcome.stream.response());
      await Future<void>.delayed(Duration.zero);
      await reader.cancel();
      expect(store.connect(token), isA<UnknownToken>());
    });
  });
}
