import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  int count(String text, String word) =>
      RegExp('\\b$word\\b').allMatches(text).length;

  group('IntrospectionQuery', () {
    test('parses as one operation and three fragments', () {
      final result = const Parser().parse(
        Source(IntrospectionQuery.full.text),
      );
      final document = (result as ParseSuccess).document;
      expect(document.definitions.map((definition) => definition.runtimeType), [
        OperationDefinition,
        FragmentDefinition,
        FragmentDefinition,
        FragmentDefinition,
      ]);
    });

    test('reads nine ofType levels by default', () {
      expect(count(const IntrospectionQuery().text, 'ofType'), 9);
    });

    test('reads no ofType level at depth 0', () {
      expect(
        count(const IntrospectionQuery(typeDepth: 0).text, 'ofType'),
        0,
      );
    });

    test('rejects a depth above 100', () {
      expect(
        () => const IntrospectionQuery(typeDepth: 101).text,
        throwsA(
          isA<RangeError>().having(
            (error) => error.message,
            'message',
            contains('Please set typeDepth to a reasonable value'),
          ),
        ),
      );
    });

    test('rejects a negative depth', () {
      expect(
        () => const IntrospectionQuery(typeDepth: -1).text,
        throwsRangeError,
      );
    });

    test('full reads every September2025 field', () {
      final text = IntrospectionQuery.full.text;
      for (final word in ['specifiedByURL', 'isRepeatable', 'isOneOf']) {
        expect(count(text, word), 1, reason: word);
      }
      expect(count(text, 'description'), 6);
      expect(count(text, 'includeDeprecated: true'), 5);
    });

    test('full does not read directive deprecation', () {
      expect(
        IntrospectionQuery.full.text,
        isNot(contains('directives(includeDeprecated: true)')),
      );
    });

    test('starts and ends with the operation and the TypeRef fragment', () {
      final text = const IntrospectionQuery(typeDepth: 1).text;
      expect(text, startsWith('query IntrospectionQuery {\n  __schema {\n'));
      expect(
        text,
        endsWith(
          'fragment TypeRef on __Type {\n'
          '  kind\n'
          '  name\n'
          '  ofType {\n'
          '    name\n'
          '    kind\n'
          '  }\n'
          '}',
        ),
      );
    });
  });
}
