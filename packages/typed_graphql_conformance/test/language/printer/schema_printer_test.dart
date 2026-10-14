// Ported from graphql-js src/language/__tests__/schema-printer-test.ts;
// see mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/dedent.dart';
import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';

void main() {
  const printer = Printer();
  const dedent = Dedent();

  group('Printer: SDL document', () {
    test('prints minimal ast', () {
      expect(
        printer.print(ScalarTypeDefinition(const Name('foo'))),
        'scalar foo',
      );
    });

    // Adapted: Dart's types admit no `{ random: 'Data' }`; the closest
    // input is a node class this library does not define.
    test('produces helpful error messages', () {
      expect(() => printer.print(_ForeignNode()), throwsArgumentError);
    });

    // Adapted: the kitchen sink needs the working-draft directive
    // extensions; nodes are immutable, so the AST cannot be altered, and
    // `isEquivalentTo` stands for a deep equality without locations.
    test('prints kitchen sink without altering ast', () {
      const port = ParserPort(
        options: ParserOptions(allowDirectiveExtensions: true),
      );
      final ast = port.document(KitchenSink.sdl);

      final printed = printer.print(ast);
      final printedAst = port.document(printed);

      expect(printedAst.isEquivalentTo(ast), isTrue);

      expect(
        printed,
        dedent('''
          """This is a description of the schema as a whole."""
          schema {
            query: QueryType
            mutation: MutationType
          }

          """
          This is a description
          of the `Foo` type.
          """
          type Foo implements Bar & Baz & Two {
            "Description of the `one` field."
            one: Type
            """This is a description of the `two` field."""
            two(
              """This is a description of the `argument` argument."""
              argument: InputType!
            ): Type
            """This is a description of the `three` field."""
            three(argument: InputType, other: String): Int
            four(argument: String = "string"): String
            five(argument: [String] = ["string", "string"]): String
            six(argument: InputType = { key: "value" }): Type
            seven(argument: Int = null): Type
            eight(argument: OneOfInputType): Type
          }

          type AnnotatedObject @onObject(arg: "value") {
            annotatedField(arg: Type = "default" @onArgumentDefinition): Type @onField
          }

          type UndefinedType

          extend type Foo {
            seven(argument: [String]): Type
          }

          extend type Foo @onType

          interface Bar {
            one: Type
            four(argument: String = "string"): String
          }

          interface AnnotatedInterface @onInterface {
            annotatedField(arg: Type @onArgumentDefinition): Type @onField
          }

          interface UndefinedInterface

          extend interface Bar implements Two {
            two(argument: InputType!): Type
          }

          extend interface Bar @onInterface

          interface Baz implements Bar & Two {
            one: Type
            two(argument: InputType!): Type
            four(argument: String = "string"): String
          }

          union Feed = Story | Article | Advert

          union AnnotatedUnion @onUnion = A | B

          union AnnotatedUnionTwo @onUnion = A | B

          union UndefinedUnion

          extend union Feed = Photo | Video

          extend union Feed @onUnion

          scalar CustomScalar

          scalar AnnotatedScalar @onScalar

          extend scalar CustomScalar @onScalar

          enum Site {
            """This is a description of the `DESKTOP` value"""
            DESKTOP
            """This is a description of the `MOBILE` value"""
            MOBILE
            "This is a description of the `WEB` value"
            WEB
          }

          enum AnnotatedEnum @onEnum {
            ANNOTATED_VALUE @onEnumValue
            OTHER_VALUE
          }

          enum UndefinedEnum

          extend enum Site {
            VR
          }

          extend enum Site @onEnum

          input InputType {
            key: String!
            answer: Int = 42
          }

          input OneOfInputType @oneOf {
            string: String
            int: Int
          }

          input AnnotatedInput @onInputObject {
            annotatedField: Type @onInputFieldDefinition
          }

          input UndefinedInput

          extend input InputType {
            other: Float = 1.23e4 @onInputFieldDefinition
          }

          extend input InputType @onInputObject

          directive @onDirectiveDefinition on DIRECTIVE_DEFINITION

          """This is a description of the `@skip` directive"""
          directive @skip(
            """This is a description of the `if` argument"""
            if: Boolean! @onArgumentDefinition
          ) @onDirectiveDefinition on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @include2(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @myRepeatableDir(name: String!) repeatable on OBJECT | INTERFACE

          extend directive @skip @onDirectiveDefinition

          extend schema @onSchema

          extend schema @onSchema {
            subscription: SubscriptionType
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
