import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/email_subscription.dart';
import '../support/execution_port.dart';
import '../support/simple_pub_sub.dart';

// Ported from the "Subscription Publish Phase" tests of graphql-js
// src/execution/__tests__/subscribe-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. `subscription.next()` is
// `StreamIterator.moveNext` and `subscription.return()` is
// `StreamIterator.cancel`.
void main() {
  const port = ExecutionPort();
  final emails = EmailSubscription();

  const alright = Email(
    from: 'yuzhi@graphql.org',
    subject: 'Alright',
    message: 'Tests are good',
    unread: true,
  );
  Map<String, Object?> payloadOf(
    String from,
    String subject, {
    required int unread,
    required int total,
    Map<String, Object?> email = const {},
  }) => {
    'data': {
      'importantEmail': {
        'email': {'from': from, 'subject': subject, ...email},
        'inbox': {'unread': unread, 'total': total},
      },
    },
  };

  Future<StreamIterator<Map<String, Object?>>> open(
    SimplePubSub<Email> pubsub, {
    Map<String, Object?>? variables,
  }) async => StreamIterator(await emails.open(pubsub, variables: variables));

  group('Subscription Publish Phase', () {
    test(
      'produces a payload for multiple subscribe in same subscription',
      () async {
        final pubsub = SimplePubSub<Email>();
        final subscription = await open(pubsub);
        final secondSubscription = await open(pubsub);

        final payload1 = subscription.moveNext();
        final payload2 = secondSubscription.moveNext();

        expect(pubsub.emit(alright), isTrue);

        final expectedPayload = payloadOf(
          'yuzhi@graphql.org',
          'Alright',
          unread: 1,
          total: 2,
        );
        expect(await payload1, isTrue);
        expect(subscription.current, expectedPayload);
        expect(await payload2, isTrue);
        expect(secondSubscription.current, expectedPayload);
        await subscription.cancel();
        await secondSubscription.cancel();
      },
    );

    test('produces a payload when queried fields are async', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(
        pubsub,
        variables: {'asyncResolver': true},
      );

      expect(pubsub.emit(alright), isTrue);

      expect(await subscription.moveNext(), isTrue);
      expect(
        subscription.current,
        payloadOf(
          'yuzhi@graphql.org',
          'Alright',
          unread: 1,
          total: 2,
          email: {'asyncSubject': 'Alright'},
        ),
      );
      await subscription.cancel();
    });

    test('produces a payload per subscription event', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      // Wait for the next subscription payload.
      final payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      // The previously waited on payload now has a value.
      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      // Another new email arrives, before subscription.next() is called.
      expect(
        pubsub.emit(
          const Email(
            from: 'hyo@graphql.org',
            subject: 'Tools',
            message: 'I <3 making things',
            unread: true,
          ),
        ),
        isTrue,
      );

      // The next waited on payload will have a value.
      expect(await subscription.moveNext(), isTrue);
      expect(
        subscription.current,
        payloadOf('hyo@graphql.org', 'Tools', unread: 2, total: 3),
      );

      // The client decides to disconnect.
      await subscription.cancel();

      // Which may result in disconnecting upstream services as well.
      expect(
        pubsub.emit(
          const Email(
            from: 'adam@graphql.org',
            subject: 'Important',
            message: 'Read me please',
            unread: true,
          ),
        ),
        isFalse,
      ); // No more listeners.

      // Awaiting a subscription after closing it results in completed results.
      expect(await subscription.moveNext(), isFalse);
    });

    test('produces a payload when there are multiple events', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      payload = subscription.moveNext();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Alright 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isTrue,
      );

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright 2', unread: 2, total: 3),
      );
      await subscription.cancel();
    });

    test('should not trigger when subscription is already done', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      payload = subscription.moveNext();
      await subscription.cancel();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Alright 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isFalse,
      );

      expect(await payload, isFalse);
    });

    test('event order is correct for multiple publishes', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Message',
            message: 'Tests are good',
            unread: true,
          ),
        ),
        isTrue,
      );

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Message 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isTrue,
      );

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Message', unread: 2, total: 3),
      );

      payload = subscription.moveNext();

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Message 2', unread: 2, total: 3),
      );
      await subscription.cancel();
    });

    group('with a field of its own', () {
      Future<List<Map<String, Object?>>> run(
        Stream<String> Function() source,
        String? Function(String message) resolve,
      ) async {
        final b = ExecutableSchemaBuilder<Object?>();
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('dummy', b.string.nullable).pure((_) => null),
            ],
          ),
          subscription: b.object<Object?>(
            'Subscription',
            fields: (t) => [
              t
                  .field('newMessage', b.string.nullable)
                  .subscribeWith<String>(
                    (parent, args, context, info) => source(),
                    (message, args, context, info) => resolve(message),
                  ),
            ],
          ),
        );
        final started = await port.subscribe<Object?>(
          schema,
          'subscription { newMessage }',
          context: null,
        );
        return switch (started) {
          SubscriptionStarted(:final results) =>
            results.map(port.withoutCodes).toList(),
          SubscriptionRejected() => throw StateError('rejected'),
        };
      }

      test('should handle error during execution of source event', () async {
        final results = await run(
          () => Stream.fromIterable(['Hello', 'Goodbye', 'Bonjour']),
          (message) {
            if (message == 'Goodbye') {
              throw const GraphQLException('Never leave.');
            }
            return message;
          },
        );

        expect(results, [
          // An error in execution is presented as such, and does not close the
          // response event stream: subsequent events are still executed.
          {
            'data': {'newMessage': 'Hello'},
          },
          {
            'data': {'newMessage': null},
            'errors': [
              {
                'message': 'Never leave.',
                'locations': [
                  {'line': 1, 'column': 16},
                ],
                'path': ['newMessage'],
              },
            ],
          },
          {
            'data': {'newMessage': 'Bonjour'},
          },
        ]);
      });

      test('should pass through error thrown in source event stream', () async {
        final results = await run(() async* {
          yield 'Hello';
          throw const GraphQLException('test error');
        }, (message) => message);

        expect(results, [
          {
            'data': {'newMessage': 'Hello'},
          },
          {
            'data': null,
            'errors': [
              {'message': 'test error'},
            ],
          },
        ]);
      });
    });
  });
}
