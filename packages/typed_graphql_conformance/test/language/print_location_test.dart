// Ported from graphql-js src/language/__tests__/printLocation-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';

void main() {
  const dedent = Dedent();
  const excerpt = SourceExcerpt();

  group('printSourceLocation', () {
    test('prints minified documents', () {
      final minifiedSource = Source(
        r'query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String){someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD...on THIRD_ERROR_HERE}}}',
      );

      String locationOf(String marker) => excerpt.of(
        minifiedSource,
        SourceLocation(1, minifiedSource.body.indexOf(marker) + 1),
      );

      expect(
        locationOf('FIRST_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:53
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        |                                                     ^
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
    '''),
      );

      expect(
        locationOf('SECOND_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:114
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
        |                                  ^
        | ..on THIRD_ERROR_HERE}}}
    '''),
      );

      expect(
        locationOf('THIRD_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:166
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
        | ..on THIRD_ERROR_HERE}}}
        |      ^
    '''),
      );
    });

    // Adapted: Source has no locationOffset; eight line breaks put the `*`
    // on line 9, so the excerpt also shows the empty line 8.
    test('prints single digit line number with no padding', () {
      final result = excerpt.of(
        Source('${'\n' * 8}*', name: 'Test'),
        const SourceLocation(9, 1),
      );

      expect(
        result,
        dedent('''
          Test:9:1
          8 |
          9 | *
            | ^
        '''),
      );
    });

    // Adapted: Source has no locationOffset; eight line breaks put the `*`
    // on line 9, so the excerpt also shows the empty line 8.
    test('prints line numbers with correct padding', () {
      final result = excerpt.of(
        Source('${'\n' * 8}*\n', name: 'Test'),
        const SourceLocation(9, 1),
      );

      expect(
        result,
        dedent('''
          Test:9:1
           8 |
           9 | *
             | ^
          10 |
        '''),
      );
    });
  });
}
