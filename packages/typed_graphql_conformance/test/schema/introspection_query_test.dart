import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

// Ported from graphql-js src/utilities/__tests__/getIntrospectionQuery-test.ts.
// graphql-js validates each query against a schema; operation validation
// arrives in M4, so the port parses it instead. Option names map to the
// `includes*` flags of IntrospectionQuery.
void main() {
  /// The text of [query], which must parse.
  String textOf(IntrospectionQuery query) {
    final text = query.text;
    expect(const Parser().parse(Source(text)), isA<ParseSuccess>());
    return text;
  }

  int count(IntrospectionQuery query, String name) =>
      RegExp('\\b$name\\b').allMatches(textOf(query)).length;

  group('getIntrospectionQuery', () {
    test('skip all "description" fields', () {
      expect(count(const IntrospectionQuery(), 'description'), 5);
      expect(
        count(
          const IntrospectionQuery(includesDescriptions: true),
          'description',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesDescriptions: false),
          'description',
        ),
        0,
      );
    });

    test('include "isRepeatable" field on directives', () {
      expect(count(const IntrospectionQuery(), 'isRepeatable'), 0);
      expect(
        count(
          const IntrospectionQuery(includesDirectiveIsRepeatable: true),
          'isRepeatable',
        ),
        1,
      );
      expect(
        count(
          const IntrospectionQuery(includesDirectiveIsRepeatable: false),
          'isRepeatable',
        ),
        0,
      );
    });

    test('include "description" field on schema', () {
      expect(count(const IntrospectionQuery(), 'description'), 5);
      expect(
        count(
          const IntrospectionQuery(includesSchemaDescription: false),
          'description',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesSchemaDescription: true),
          'description',
        ),
        6,
      );
      expect(
        count(
          const IntrospectionQuery(
            includesDescriptions: false,
            includesSchemaDescription: true,
          ),
          'description',
        ),
        0,
      );
    });

    test('include "specifiedBy" field', () {
      expect(count(const IntrospectionQuery(), 'specifiedByURL'), 0);
      expect(
        count(
          const IntrospectionQuery(includesSpecifiedByUrl: true),
          'specifiedByURL',
        ),
        1,
      );
      expect(
        count(
          const IntrospectionQuery(includesSpecifiedByUrl: false),
          'specifiedByURL',
        ),
        0,
      );
    });

    test('include "isDeprecated" field on input values', () {
      expect(count(const IntrospectionQuery(), 'isDeprecated'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'isDeprecated',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'isDeprecated',
        ),
        2,
      );
    });

    test('include "deprecationReason" field on input values', () {
      expect(count(const IntrospectionQuery(), 'deprecationReason'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'deprecationReason',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'deprecationReason',
        ),
        2,
      );
    });

    test('include "isOneOf" field on input objects', () {
      expect(count(const IntrospectionQuery(), 'isOneOf'), 0);
      expect(
        count(const IntrospectionQuery(includesOneOf: true), 'isOneOf'),
        1,
      );
      expect(
        count(const IntrospectionQuery(includesOneOf: false), 'isOneOf'),
        0,
      );
    });

    test('include deprecated input field and args', () {
      expect(count(const IntrospectionQuery(), 'includeDeprecated: true'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'includeDeprecated: true',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'includeDeprecated: true',
        ),
        2,
      );
    });

    test('include "isDeprecated" field on directives', () {
      expect(count(const IntrospectionQuery(), 'isDeprecated'), 2);
      expect(
        count(
          const IntrospectionQuery(includesDirectiveDeprecation: true),
          'isDeprecated',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesDirectiveDeprecation: false),
          'isDeprecated',
        ),
        2,
      );
    });

    test('include "deprecationReason" field on directives', () {
      const opening = 'directives(includeDeprecated: true) {';
      expect(textOf(const IntrospectionQuery()), isNot(contains(opening)));
      expect(count(const IntrospectionQuery(), 'deprecationReason'), 2);
      const withDeprecation = IntrospectionQuery(
        includesDirectiveDeprecation: true,
      );
      expect(textOf(withDeprecation), contains(opening));
      expect(count(withDeprecation, 'deprecationReason'), 3);
      const without = IntrospectionQuery(includesDirectiveDeprecation: false);
      expect(textOf(without), isNot(contains(opening)));
      expect(count(without, 'deprecationReason'), 2);
    });

    test('throw error if typeDepth is too high', () {
      expect(
        () => const IntrospectionQuery(typeDepth: 101).text,
        throwsA(
          isA<RangeError>().having(
            (error) => error.message,
            'message',
            'Please set typeDepth to a reasonable value between 0 and 100; '
                'the default is 9.',
          ),
        ),
      );
    });
  });
}
