import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/src/policy/token_renewal.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// A terminating link whose n-th call is the n-th builder; a builder may
/// throw instead of returning a stream.
final class ScriptedLink extends Link {
  ScriptedLink(this.script);

  final List<Stream<LinkResult> Function()> script;
  int callCount = 0;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      script[callCount++]();
}

void main() {
  final hello = JsonObject({'hello': const JsonString('world')});
  final query = LinkRequest.of(const HelloQuery());
  const networkFailure = NetworkFailure(FormatException('down'));

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  Stream<LinkResult> lost() => Stream.value(const LinkFailure(networkFailure));

  Stream<LinkResult> broken() => throw StateError('broken link');

  Stream<LinkResult> payload() =>
      Stream.value(LinkPayload(ExecutionResult(hello)));

  /// Listens to [link] and returns what it emitted, with its errors and end.
  ({List<Object> events, bool Function() isDone}) listenTo(Link link) {
    final events = <Object>[];
    var isDone = false;
    link
        .request(query, unterminated)
        .listen(
          events.add,
          onError: events.add,
          onDone: () => isDone = true,
        );
    return (events: events, isDone: () => isDone);
  }

  group('a link that throws from request', () {
    test('ends a retried request with the error, not an uncaught one', () {
      fakeAsync((async) {
        final heard = listenTo(
          Link.from([
            RetryLink(),
            ScriptedLink([lost, broken]),
          ]),
        );
        async.elapse(const Duration(seconds: 10));
        expect(heard.events.last, isA<StateError>());
        expect(heard.isDone(), isTrue);
      });
    });

    test('ends a request that is sent again after a refresh', () async {
      final scripted = ScriptedLink([
        () => Stream.value(LinkFailure(HttpStatusFailure(401))),
        broken,
      ]);
      final link = Link.from([
        AuthLink(token: () => 'old', refresh: () async => 'new'),
        scripted,
      ]);
      final heard = listenTo(link);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(heard.events.last, isA<StateError>());
      expect(heard.isDone(), isTrue);
    });

    test('ends a request whose first send throws', () async {
      final heard = listenTo(
        Link.from([
          AuthLink(token: () => 'old'),
          ScriptedLink([broken]),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(heard.events.single, isA<StateError>());
      expect(heard.isDone(), isTrue);
    });

    test('ends a persisted query that is sent again with the text', () async {
      final notFound = LinkPayload(
        ExecutionResult(
          null,
          errors: [
            GraphQLError(
              'x',
              extensions: JsonObject({
                'code': const JsonString('PERSISTED_QUERY_NOT_FOUND'),
              }),
            ),
          ],
        ),
      );
      final heard = listenTo(
        Link.from([
          PersistedQueryLink(),
          ScriptedLink([() => Stream.value(notFound), broken]),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(heard.events.last, isA<StateError>());
      expect(heard.isDone(), isTrue);
    });

    test('ends a persisted query whose first send throws', () async {
      final heard = listenTo(
        Link.from([
          PersistedQueryLink(),
          ScriptedLink([broken]),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(heard.events.single, isA<StateError>());
      expect(heard.isDone(), isTrue);
    });
  });

  group('RetryLink after a payload', () {
    test('does not retry a failure that follows a delivered payload', () {
      fakeAsync((async) {
        final scripted = ScriptedLink([
          () => Stream.fromIterable([
            LinkPayload(ExecutionResult(hello)),
            const LinkFailure(networkFailure),
          ]),
          payload,
        ]);
        final heard = listenTo(Link.from([RetryLink(), scripted]));
        async.elapse(const Duration(seconds: 10));
        expect(scripted.callCount, 1);
        expect(heard.events, hasLength(2));
        expect(heard.events.first, isA<LinkPayload>());
        expect(heard.events.last, isA<LinkFailure>());
      });
    });
  });

  group('secrets in logs', () {
    test('RequestHeaders prints the names, not the values', () {
      final text = RequestHeaders({'Authorization': 'Bearer secret'})
          .toString();
      expect(text, contains('authorization'));
      expect(text, isNot(contains('secret')));
    });

    test('LinkContext prints no header value', () {
      final text = LinkContext([
        RequestHeaders({'Authorization': 'Bearer secret'}),
      ]).toString();
      expect(text, isNot(contains('secret')));
    });
  });

  group('TokenRenewal after a failed refresh', () {
    test('does not hand back a token that was refused', () async {
      var reads = 0;
      var refreshes = 0;
      final renewal = TokenRenewal(
        () async {
          reads++;
          // The second read is slow: a whole refresh fails while it waits.
          if (reads == 2) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return reads == 1 ? 'old' : 'fresh1';
        },
        () async {
          refreshes++;
          if (refreshes == 2) {
            throw const FormatException('refresh down');
          }
          return 'fresh$refreshes';
        },
      );
      // 'fresh1' is remembered as the last refreshed token.
      expect(await renewal.renewed('old'), 'fresh1');
      final slow = renewal.renewed('fresh1');
      await expectLater(renewal.renewed('fresh1'), throwsFormatException);
      // The slow caller must not receive 'fresh1', which was refused.
      expect(await slow, 'fresh3');
    });
  });
}
