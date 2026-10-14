import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Adapted from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// extensions in the document that defines the type. graphql-js keeps the
// extension nodes (`extensionASTNodes`); the model keeps only the span of
// the definition, so those checks are dropped. The SDL is dedented, so a
// span's text is the definition as graphql-js prints its node.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Schema Builder', () {
    test('Correctly extend scalar type', () {
      final schema = port.build(
        dedent('''
          scalar SomeScalar
          extend scalar SomeScalar @foo
          extend scalar SomeScalar @bar

          directive @foo on SCALAR
          directive @bar on SCALAR
        '''),
      );
      final someScalar = port.assertType<ScalarType>(schema, 'SomeScalar');
      // graphql-js prints `scalar SomeScalar`: it drops directives other
      // than @deprecated, @specifiedBy and @oneOf.
      expect(port.printType(someScalar), 'scalar SomeScalar @foo @bar');
      expect(someScalar.span?.text, 'scalar SomeScalar');
    });

    test('Correctly extend object type', () {
      final schema = port.build(
        dedent('''
          type SomeObject implements Foo {
            first: String
          }

          extend type SomeObject implements Bar {
            second: Int
          }

          extend type SomeObject implements Baz {
            third: Float
          }

          interface Foo
          interface Bar
          interface Baz
        '''),
      );
      final someObject = port.assertType<ObjectType>(schema, 'SomeObject');
      expect(
        port.printType(someObject),
        dedent('''
          type SomeObject implements Foo & Bar & Baz {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someObject.span?.text,
        dedent('''
          type SomeObject implements Foo {
            first: String
          }
        '''),
      );
    });

    test('Correctly extend interface type', () {
      final schema = port.build(
        dedent('''
          interface SomeInterface {
            first: String
          }

          extend interface SomeInterface {
            second: Int
          }

          extend interface SomeInterface {
            third: Float
          }
        '''),
      );
      final someInterface = port.assertType<InterfaceType>(
        schema,
        'SomeInterface',
      );
      expect(
        port.printType(someInterface),
        dedent('''
          interface SomeInterface {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someInterface.span?.text,
        dedent('''
          interface SomeInterface {
            first: String
          }
        '''),
      );
    });

    test('Correctly extend union type', () {
      final schema = port.build(
        dedent('''
          union SomeUnion = FirstType
          extend union SomeUnion = SecondType
          extend union SomeUnion = ThirdType

          type FirstType
          type SecondType
          type ThirdType
        '''),
      );
      final someUnion = port.assertType<UnionType>(schema, 'SomeUnion');
      expect(
        port.printType(someUnion),
        'union SomeUnion = FirstType | SecondType | ThirdType',
      );
      expect(someUnion.span?.text, 'union SomeUnion = FirstType');
    });

    test('Correctly extend enum type', () {
      final schema = port.build(
        dedent('''
          enum SomeEnum {
            FIRST
          }

          extend enum SomeEnum {
            SECOND
          }

          extend enum SomeEnum {
            THIRD
          }
        '''),
      );
      final someEnum = port.assertType<EnumType>(schema, 'SomeEnum');
      expect(
        port.printType(someEnum),
        dedent('''
          enum SomeEnum {
            FIRST
            SECOND
            THIRD
          }
        '''),
      );
      expect(
        someEnum.span?.text,
        dedent('''
          enum SomeEnum {
            FIRST
          }
        '''),
      );
    });

    test('Correctly extend input object type', () {
      final schema = port.build(
        dedent('''
          input SomeInput {
            first: String
          }

          extend input SomeInput {
            second: Int
          }

          extend input SomeInput {
            third: Float
          }
        '''),
      );
      final someInput = port.assertType<InputObjectType>(schema, 'SomeInput');
      expect(
        port.printType(someInput),
        dedent('''
          input SomeInput {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someInput.span?.text,
        dedent('''
          input SomeInput {
            first: String
          }
        '''),
      );
    });
  });
}
