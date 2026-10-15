import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/SingleFieldSubscriptionsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const SingleFieldSubscriptionsRule()).withSchema('''
  type Message {
    body: String
    sender: String
  }

  type SubscriptionRoot {
    importantEmails: [String]
    notImportantEmails: [String]
    moreImportantEmails: [String]
    spamEmails: [String]
    deletedEmails: [String]
    newMessage: Message
  }

  type QueryRoot {
    dummy: String
  }

  schema {
    query: QueryRoot
    subscription: SubscriptionRoot
  }
''');

  group('Validate: Subscriptions with single field', () {
    test('valid subscription', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
      }
    '''),
        isEmpty,
      );
    });

    test('valid subscription with fragment', () {
      // From https://spec.graphql.org/draft/#example-13061
      expect(
        port.errors('''
      subscription sub {
        ...newMessageFields
      }

      fragment newMessageFields on SubscriptionRoot {
        newMessage {
          body
          sender
        }
      }
    '''),
        isEmpty,
      );
    });

    test('valid subscription with fragment and field', () {
      // From https://spec.graphql.org/draft/#example-13061
      expect(
        port.errors('''
      subscription sub {
        newMessage {
          body
        }
        ...newMessageFields
      }

      fragment newMessageFields on SubscriptionRoot {
        newMessage {
          body
          sender
        }
      }
    '''),
        isEmpty,
      );
    });

    test('fails with more than one root field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        notImportantEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9',
        ],
      );
    });

    test('fails with more than one root field including introspection', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9',
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 4:9',
        ],
      );
    });

    test('fails with more than one root field including aliased introspection via fragment', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        ...Introspection
      }
      fragment Introspection on SubscriptionRoot {
        typename: __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 7:9',
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 7:9',
        ],
      );
    });

    test('fails with many more than one root field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        notImportantEmails
        spamEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9 5:9',
        ],
      );
    });

    test('fails with many more than one root field via fragments', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        ... {
          more: moreImportantEmails
        }
        ...NotImportantEmails
      }
      fragment NotImportantEmails on SubscriptionRoot {
        notImportantEmails
        deleted: deletedEmails
        ...SpamEmails
      }
      fragment SpamEmails on SubscriptionRoot {
        spamEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 5:11 10:9 11:9 15:9',
        ],
      );
    });

    test('does not infinite loop on recursive fragments', () {
      expect(
        port.errors('''
      subscription NoInfiniteLoop {
        ...A
      }
      fragment A on SubscriptionRoot {
        ...A
      }
    '''),
        isEmpty,
      );
    });

    test(
      'fails with many more than one root field via fragments (anonymous)',
      () {
        expect(
          port.errors('''
      subscription {
        importantEmails
        ... {
          more: moreImportantEmails
          ...NotImportantEmails
        }
        ...NotImportantEmails
      }
      fragment NotImportantEmails on SubscriptionRoot {
        notImportantEmails
        deleted: deletedEmails
        ... {
          ... {
            archivedEmails
          }
        }
        ...SpamEmails
      }
      fragment SpamEmails on SubscriptionRoot {
        spamEmails
        ...NonExistentFragment
      }
    '''),
          [
            'Anonymous Subscription must select only one top level field. @ 5:11 11:9 12:9 15:13 21:9',
          ],
        );
      },
    );

    test('fails with more than one root field in anonymous subscriptions', () {
      expect(
        port.errors('''
      subscription {
        importantEmails
        notImportantEmails
      }
    '''),
        [
          'Anonymous Subscription must select only one top level field. @ 4:9',
        ],
      );
    });

    test('fails with introspection field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 3:9',
        ],
      );
    });

    test('fails with introspection field in anonymous subscription', () {
      expect(
        port.errors('''
      subscription {
        __typename
      }
    '''),
        [
          'Anonymous Subscription must not select an introspection top level field. @ 3:9',
        ],
      );
    });

    test('fails with @skip or @include directive', () {
      expect(
        port.errors(r'''
      subscription RequiredRuntimeValidation($bool: Boolean!) {
        newMessage @include(if: $bool) {
          body
          sender
        }
        disallowedSecondRootField @skip(if: $bool)
      }
    '''),
        [
          'Subscription "RequiredRuntimeValidation" must not use `@skip` or `@include` directives in the top level selection. @ 3:20 7:35',
        ],
      );
    });

    test(
      'fails with @skip or @include directive in anonymous subscription',
      () {
        expect(
          port.errors(r'''
      subscription ($bool: Boolean!) {
        newMessage @include(if: $bool) {
          body
          sender
        }
        disallowedSecondRootField @skip(if: $bool)
      }
    '''),
          [
            'Anonymous Subscription must not use `@skip` or `@include` directives in the top level selection. @ 3:20 7:35',
          ],
        );
      },
    );

    test('skips if not subscription type', () {
      final emptySchema = port.withSchema('''
      type Query {
        dummy: String
      }
    ''');
      expect(
        emptySchema.errors('''
        subscription {
          __typename
        }
      '''),
        isEmpty,
      );
    });
  });
}
