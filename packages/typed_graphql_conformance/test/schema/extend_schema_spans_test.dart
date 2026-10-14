import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Adapted from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// the AST nodes of new and extended elements. The model keeps the span of
// each definition instead of its node, and no extension nodes; the texts
// are dedented, so a span's text is the definition as graphql-js prints
// its node.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('correctly assign AST nodes to new and extended types', () {
      final schema = port.build('''
        type Query

        scalar SomeScalar
        enum SomeEnum
        union SomeUnion
        input SomeInput
        type SomeObject
        interface SomeInterface

        directive @foo on SCALAR
      ''');
      final firstExtension = dedent('''
        extend type Query {
          newField(testArg: TestInput): TestEnum
        }

        extend scalar SomeScalar @foo

        extend enum SomeEnum {
          NEW_VALUE
        }

        extend union SomeUnion = SomeObject

        extend input SomeInput {
          newField: String
        }

        extend interface SomeInterface {
          newField: String
        }

        enum TestEnum {
          TEST_VALUE
        }

        input TestInput {
          testInputField: TestEnum
        }
      ''');
      final secondExtension = dedent('''
        extend type Query {
          oneMoreNewField: TestUnion
        }

        extend scalar SomeScalar @test

        extend enum SomeEnum {
          ONE_MORE_NEW_VALUE
        }

        extend union SomeUnion = TestType

        extend input SomeInput {
          oneMoreNewField: String
        }

        extend interface SomeInterface {
          oneMoreNewField: String
        }

        union TestUnion = TestType

        interface TestInterface {
          interfaceField: String
        }

        type TestType implements TestInterface {
          interfaceField: String
        }

        directive @test(arg: Int) repeatable on FIELD | SCALAR
      ''');
      final extendedSchema = port.extend(schema, firstExtension);
      final extendedTwiceSchema = port.extend(extendedSchema, secondExtension);
      final extendedInOneGoSchema = port.extend(
        schema,
        '$firstExtension\n\n$secondExtension',
      );
      expect(
        port.print(extendedInOneGoSchema),
        port.print(extendedTwiceSchema),
      );

      final query = port.assertType<ObjectType>(extendedTwiceSchema, 'Query');
      final someEnum = port.assertType<EnumType>(
        extendedTwiceSchema,
        'SomeEnum',
      );
      final someInput = port.assertType<InputObjectType>(
        extendedTwiceSchema,
        'SomeInput',
      );
      final someInterface = port.assertType<InterfaceType>(
        extendedTwiceSchema,
        'SomeInterface',
      );
      final testInput = port.assertType<InputObjectType>(
        extendedTwiceSchema,
        'TestInput',
      );
      final testEnum = port.assertType<EnumType>(
        extendedTwiceSchema,
        'TestEnum',
      );
      final testInterface = port.assertType<InterfaceType>(
        extendedTwiceSchema,
        'TestInterface',
      );
      final testType = port.assertType<ObjectType>(
        extendedTwiceSchema,
        'TestType',
      );
      final testDirective = extendedTwiceSchema.directiveNamed('test');

      expect(
        [
          testInput.span,
          testEnum.span,
          extendedTwiceSchema.typeNamed('TestUnion')?.span,
          testInterface.span,
          testType.span,
          testDirective?.span,
        ].map((span) => span?.text),
        [
          'input TestInput {\n  testInputField: TestEnum\n}',
          'enum TestEnum {\n  TEST_VALUE\n}',
          'union TestUnion = TestType',
          'interface TestInterface {\n  interfaceField: String\n}',
          'type TestType implements TestInterface {\n'
              '  interfaceField: String\n'
              '}',
          'directive @test(arg: Int) repeatable on FIELD | SCALAR',
        ],
      );

      final newField = query.fieldNamed('newField');
      expect(newField?.span?.text, 'newField(testArg: TestInput): TestEnum');
      expect(newField?.arguments.first.span?.text, 'testArg: TestInput');
      expect(
        query.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: TestUnion',
      );
      expect(someEnum.valueNamed('NEW_VALUE')?.span?.text, 'NEW_VALUE');
      expect(
        someEnum.valueNamed('ONE_MORE_NEW_VALUE')?.span?.text,
        'ONE_MORE_NEW_VALUE',
      );
      expect(someInput.fieldNamed('newField')?.span?.text, 'newField: String');
      expect(
        someInput.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: String',
      );
      expect(
        someInterface.fieldNamed('newField')?.span?.text,
        'newField: String',
      );
      expect(
        someInterface.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: String',
      );
      expect(
        testInput.fieldNamed('testInputField')?.span?.text,
        'testInputField: TestEnum',
      );
      expect(testEnum.valueNamed('TEST_VALUE')?.span?.text, 'TEST_VALUE');
      expect(
        testInterface.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(
        testType.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(testDirective?.arguments.first.span?.text, 'arg: Int');
    });
  });
}
