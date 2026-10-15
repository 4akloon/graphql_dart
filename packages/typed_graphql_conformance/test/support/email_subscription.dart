import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'simple_pub_sub.dart';

/// An email of graphql-js's subscribe-test.
final class Email {
  /// Creates an email.
  const Email({
    required this.from,
    required this.subject,
    required this.message,
    required this.unread,
  });

  /// The sender.
  final String from;

  /// The subject.
  final String subject;

  /// The body.
  final String message;

  /// Whether it was not read yet.
  final bool unread;
}

/// The emails of one subscription, which the source appends to.
final class EmailInbox {
  /// Creates an inbox holding [emails].
  EmailInbox(this.emails);

  /// Every email so far.
  final List<Email> emails;
}

/// What the `importantEmail` field holds for one event.
final class EmailEvent {
  /// Creates the event of [email] in [inbox].
  const EmailEvent(this.email, this.inbox);

  /// The new email.
  final Email email;

  /// The inbox it arrived in.
  final EmailInbox inbox;
}

/// The root value of a subscription: where its events come from.
final class EmailSource {
  /// Creates a source on [pubsub].
  EmailSource(this.pubsub)
    : emails = [
        const Email(
          from: 'joe@graphql.org',
          subject: 'Hello',
          message: 'Hello World',
          unread: false,
        ),
      ];

  /// Where the new emails are published.
  final SimplePubSub<Email> pubsub;

  /// The inbox's emails, starting with one.
  final List<Email> emails;
}

/// graphql-js's `emailSchema` and `createSubscription` of
/// `execution/__tests__/subscribe-test.ts`.
///
/// Spec 18.10 of M5: the source of `importantEmail` is declared on the field
/// (graphql-js reads it from the root value) and each event is the field's
/// value, so the source builds the `EmailEvent` that graphql-js's mapping
/// function wraps in `{ importantEmail: ... }`.
final class EmailSubscription {
  /// Builds the schema.
  EmailSubscription() {
    final b = ExecutableSchemaBuilder<Object?>();
    final email = b.object<Email>(
      'Email',
      fields: (t) => [
        t.field('from', b.string.nullable).pure((e) => e.from),
        t.field('subject', b.string.nullable).pure((e) => e.subject),
        t
            .field('asyncSubject', b.string.nullable)
            .resolve((e, args, context, info) => Future.value(e.subject)),
        t.field('message', b.string.nullable).pure((e) => e.message),
        t.field('unread', b.boolean.nullable).pure((e) => e.unread),
      ],
    );
    final inbox = b.object<EmailInbox>(
      'Inbox',
      fields: (t) => [
        t.field('total', b.int.nullable).pure((i) => i.emails.length),
        t
            .field('unread', b.int.nullable)
            .pure((i) => i.emails.where((e) => e.unread).length),
        t
            .field('emails', b.list(email.nullable).nullable)
            .pure((i) => i.emails),
      ],
    );
    final event = b.object<EmailEvent>(
      'EmailEvent',
      fields: (t) => [
        t.field('email', email.nullable).pure((e) => e.email),
        t.field('inbox', inbox.nullable).pure((e) => e.inbox),
      ],
    );
    final priority = Arg('priority', b.int.nullable);
    schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('inbox', inbox.nullable).pure((_) => EmailInbox(const [])),
        ],
      ),
      subscription: b.object<EmailSource>(
        'Subscription',
        fields: (t) => [
          t.field('importantEmail', event.nullable, args: [priority]).subscribe(
            (source, args, context, info) {
              final inbox = EmailInbox(source.emails);
              return source.pubsub.getSubscriber(
                (newEmail) {
                  source.emails.add(newEmail);
                  return EmailEvent(newEmail, inbox);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// The email schema.
  late final ExecutableSchema<Object?> schema;

  /// The subscription document of `createSubscription`; it starts with the
  /// blank line of the JavaScript template, so locations match.
  static const String document = r'''

    subscription (
      $priority: Int = 0
      $shouldDefer: Boolean = false
      $shouldStream: Boolean = false
      $asyncResolver: Boolean = false
    ) {
      importantEmail(priority: $priority) {
        email {
          from
          subject
          ... @include(if: $asyncResolver) {
            asyncSubject
          }
        }
        ... @defer(if: $shouldDefer) {
          inbox {
            emails @include(if: $shouldStream) @stream(if: $shouldStream)
            unread
            total
          }
        }
      }
    }
  ''';

  /// Starts the subscription on [pubsub] with [variables], and returns its
  /// responses as JSON (codes dropped).
  Future<Stream<Map<String, Object?>>> open(
    SimplePubSub<Email> pubsub, {
    Map<String, Object?>? variables,
  }) async {
    const port = ExecutionPort();
    final started = await port.subscribe<Object?>(
      schema,
      document,
      context: null,
      variables: variables == null ? null : port.variablesOf(variables),
      options: ExecutionOptions(
        rootValue: EmailSource(pubsub),
        maskErrors: false,
      ),
    );
    return switch (started) {
      SubscriptionStarted(:final results) => results.map(port.withoutCodes),
      SubscriptionRejected(:final error) => throw StateError('$error'),
    };
  }
}
