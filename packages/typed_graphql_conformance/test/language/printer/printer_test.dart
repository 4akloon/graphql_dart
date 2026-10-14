// Ported from graphql-js src/language/__tests__/printer-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/dedent.dart';
import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();
  const printer = Printer();
  const dedent = Dedent();

  group('Printer: Query document', () {
    test('prints minimal ast', () {
      expect(printer.print(Field(null, const Name('foo'))), 'foo');
    });

    // Adapted: Dart's types admit no `{ random: 'Data' }`; the closest
    // input is a node class this library does not define.
    test('produces helpful error messages', () {
      expect(() => printer.print(_ForeignNode()), throwsArgumentError);
    });

    test('correctly prints non-query operations without name', () {
      final queryAstShorthanded = port.document('query { id, name }');
      expect(
        printer.print(queryAstShorthanded),
        dedent('''
          {
            id
            name
          }
        '''),
      );

      final mutationAst = port.document('mutation { id, name }');
      expect(
        printer.print(mutationAst),
        dedent('''
          mutation {
            id
            name
          }
        '''),
      );

      final queryAstWithArtifacts = port.document(
        r'query ($foo: TestType) @testDirective { id, name }',
      );
      expect(
        printer.print(queryAstWithArtifacts),
        dedent(r'''
          query ($foo: TestType) @testDirective {
            id
            name
          }
        '''),
      );

      final mutationAstWithArtifacts = port.document(
        r'mutation ($foo: TestType) @testDirective { id, name }',
      );
      expect(
        printer.print(mutationAstWithArtifacts),
        dedent(r'''
          mutation ($foo: TestType) @testDirective {
            id
            name
          }
        '''),
      );
    });

    test('prints query with variable directives', () {
      final printed = printer.print(
        port.document(
          r'query ($foo: TestType = { a: 123 } @testDirective(if: true) @test) { id }',
        ),
      );
      expect(
        printed,
        dedent(r'''
          query ($foo: TestType = { a: 123 } @testDirective(if: true) @test) {
            id
          }
        '''),
      );
    });

    test('keeps arguments on one line if line is short (<= 80 chars)', () {
      final printed = printer.print(
        port.document('{trip(wheelchair:false arriveBy:false){dateTime}}'),
      );
      expect(
        printed,
        dedent('''
          {
            trip(wheelchair: false, arriveBy: false) {
              dateTime
            }
          }
        '''),
      );
    });

    test('puts arguments on multiple lines if line is long (> 80 chars)', () {
      final printed = printer.print(
        port.document(
          '{trip(wheelchair:false arriveBy:false includePlannedCancellations:true transitDistanceReluctance:2000){dateTime}}',
        ),
      );
      expect(
        printed,
        dedent('''
          {
            trip(
              wheelchair: false
              arriveBy: false
              includePlannedCancellations: true
              transitDistanceReluctance: 2000
            ) {
              dateTime
            }
          }
        '''),
      );
    });

    test(
      'puts large object values on multiple lines if line is long (> 80 chars)',
      () {
        final printed = printer.print(
          port.document(
            '{trip(obj:{wheelchair:false,smallObj:{a: 1},largeObj:{wheelchair:false,smallObj:{a: 1},arriveBy:false,includePlannedCancellations:true,transitDistanceReluctance:2000,anotherLongFieldName:"Lots and lots and lots and lots of text"},arriveBy:false,includePlannedCancellations:true,transitDistanceReluctance:2000,anotherLongFieldName:"Lots and lots and lots and lots of text"}){dateTime}}',
          ),
        );
        expect(
          printed,
          dedent('''
      {
        trip(
          obj: {
            wheelchair: false
            smallObj: { a: 1 }
            largeObj: {
              wheelchair: false
              smallObj: { a: 1 }
              arriveBy: false
              includePlannedCancellations: true
              transitDistanceReluctance: 2000
              anotherLongFieldName: "Lots and lots and lots and lots of text"
            }
            arriveBy: false
            includePlannedCancellations: true
            transitDistanceReluctance: 2000
            anotherLongFieldName: "Lots and lots and lots and lots of text"
          }
        ) {
          dateTime
        }
      }
          '''),
        );
      },
    );

    test(
      'puts large list values on multiple lines if line is long (> 80 chars)',
      () {
        final printed = printer.print(
          port.document(
            '{trip(list:[["small array", "small", "small"], ["Lots and lots and lots and lots of text", "Lots and lots and lots and lots of text", "Lots and lots and lots and lots of text"]]){dateTime}}',
          ),
        );
        expect(
          printed,
          dedent('''
      {
        trip(
          list: [
            ["small array", "small", "small"]
            [
              "Lots and lots and lots and lots of text"
              "Lots and lots and lots and lots of text"
              "Lots and lots and lots and lots of text"
            ]
          ]
        ) {
          dateTime
        }
      }
          '''),
        );
      },
    );

    test('prints fragment', () {
      final printed = printer.print(
        port.document('"Fragment description" fragment Foo on Bar { baz }'),
      );
      expect(
        printed,
        dedent('''
          "Fragment description"
          fragment Foo on Bar {
            baz
          }
        '''),
      );
    });

    // Adapted: nodes are immutable, so the AST cannot be altered, and
    // `isEquivalentTo` stands for a deep equality without locations.
    test('prints kitchen sink without altering ast', () {
      final ast = port.document(KitchenSink.query);

      final printed = printer.print(ast);
      final printedAst = port.document(printed);

      expect(printedAst.isEquivalentTo(ast), isTrue);

      expect(
        printed,
        dedent(r'''
      "Query description"
      query queryName(
      "Very complex variable"
      $foo: ComplexType
      $site: Site = MOBILE
      ) @onQuery {
        whoever123is: node(id: [123, 456]) {
          id
          ... on User @onInlineFragment {
            field2 {
              id
              alias: field1(first: 10, after: $foo) @include(if: $foo) {
                id
                ...frag @onFragmentSpread
              }
            }
          }
          ... @skip(unless: $foo) {
            id
          }
          ... {
            id
          }
        }
      }

      mutation likeStory @onMutation {
        like(story: 123) @onField {
          story {
            id @onField
          }
        }
      }

      subscription StoryLikeSubscription($input: StoryLikeSubscribeInput @onVariableDefinition) @onSubscription {
        storyLikeSubscribe(input: $input) {
          story {
            likers {
              count
            }
            likeSentence {
              text
            }
          }
        }
      }

      """Fragment description"""
      fragment frag on Friend @onFragmentDefinition {
        foo(
          size: $size
          bar: $b
          obj: { key: "value", block: """
          block string uses \"""
          """ }
        )
      }

      {
        unnamed(truthy: true, falsy: false, nullish: null)
        query
      }

      {
        __typename
      }
        '''),
      );
    });
  });
}

/// A node class this library does not define, standing in for graphql-js's
/// `{ random: 'Data' }`.
final class _ForeignNode extends Node {
  @override
  List<Node> get children => const [];

  // A wider parameter type than Node's: `ChildReader` is not public API,
  // and a node built outside the library never rebuilds.
  @override
  Node rebuildFrom(Object? read) => this;
}
