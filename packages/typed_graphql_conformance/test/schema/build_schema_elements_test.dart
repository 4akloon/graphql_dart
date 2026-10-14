import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// deprecation, spans, root types and the built-in names. Where graphql-js
// calls validateSchema, the check returns with schema validation in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('Schema Builder', () {
    test('Supports @deprecated', () {
      final sdl = dedent('''
        enum MyEnum {
          VALUE
          OLD_VALUE @deprecated
          OTHER_VALUE @deprecated(reason: "Terrible reasons")
        }

        input MyInput {
          oldInput: String @deprecated
          otherInput: String @deprecated(reason: "Use newInput")
          newInput: String
        }

        type Query {
          field1: String @deprecated
          field2: Int @deprecated(reason: "Because I said so")
          enum: MyEnum
          field3(oldArg: String @deprecated, arg: String): String
          field4(oldArg: String @deprecated(reason: "Why not?"), arg: String): String
          field5(arg: MyInput): String
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      final myEnum = port.assertType<EnumType>(schema, 'MyEnum');
      expect(myEnum.valueNamed('VALUE')?.deprecationReason, isNull);
      expect(
        myEnum.valueNamed('OLD_VALUE')?.deprecationReason,
        'No longer supported',
      );
      expect(
        myEnum.valueNamed('OTHER_VALUE')?.deprecationReason,
        'Terrible reasons',
      );

      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        query.fieldNamed('field1')?.deprecationReason,
        'No longer supported',
      );
      expect(
        query.fieldNamed('field2')?.deprecationReason,
        'Because I said so',
      );

      final myInput = port.assertType<InputObjectType>(schema, 'MyInput');
      expect(myInput.fieldNamed('newInput')?.deprecationReason, isNull);
      expect(
        myInput.fieldNamed('oldInput')?.deprecationReason,
        'No longer supported',
      );
      expect(
        myInput.fieldNamed('otherInput')?.deprecationReason,
        'Use newInput',
      );

      expect(
        query.fieldNamed('field3')?.arguments.first.deprecationReason,
        'No longer supported',
      );
      expect(
        query.fieldNamed('field4')?.arguments.first.deprecationReason,
        'Why not?',
      );
    });

    test('Supports @specifiedBy', () {
      final sdl = dedent('''
        scalar Foo @specifiedBy(url: "https://example.com/foo_spec")

        type Query {
          foo: Foo @deprecated
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      expect(
        port.assertType<ScalarType>(schema, 'Foo').specifiedByUrl,
        'https://example.com/foo_spec',
      );
    });

    test('Correctly assign AST nodes', () {
      // graphql-js compares the AST nodes; the model keeps their spans.
      final sdl = dedent('''
        schema {
          query: Query
        }

        type Query {
          testField(testArg: TestInput): TestUnion
        }

        input TestInput {
          testInputField: TestEnum
        }

        enum TestEnum {
          TEST_VALUE
        }

        union TestUnion = TestType

        interface TestInterface {
          interfaceField: String
        }

        type TestType implements TestInterface {
          interfaceField: String
        }

        scalar TestScalar

        directive @test(arg: TestScalar) on FIELD
      ''');
      final schema = port.build(sdl);
      final query = port.assertType<ObjectType>(schema, 'Query');
      final testInput = port.assertType<InputObjectType>(schema, 'TestInput');
      final testEnum = port.assertType<EnumType>(schema, 'TestEnum');
      final testInterface = port.assertType<InterfaceType>(
        schema,
        'TestInterface',
      );
      final testType = port.assertType<ObjectType>(schema, 'TestType');
      final testDirective = schema.directiveNamed('test');

      expect(
        [
          schema.span,
          query.span,
          testInput.span,
          testEnum.span,
          schema.typeNamed('TestUnion')?.span,
          testInterface.span,
          testType.span,
          schema.typeNamed('TestScalar')?.span,
          testDirective?.span,
        ].map((span) => span?.text),
        port.document(sdl).definitions.map(const Printer().print),
      );

      final testField = query.fieldNamed('testField');
      expect(
        testField?.span?.text,
        'testField(testArg: TestInput): TestUnion',
      );
      expect(testField?.arguments.first.span?.text, 'testArg: TestInput');
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
      expect(testDirective?.arguments.first.span?.text, 'arg: TestScalar');
    });

    test('Root operation types with custom names', () {
      final schema = port.build('''
        schema {
          query: SomeQuery
          mutation: SomeMutation
          subscription: SomeSubscription
        }
        type SomeQuery
        type SomeMutation
        type SomeSubscription
      ''');
      expect(schema.queryTypeName, 'SomeQuery');
      expect(schema.mutationTypeName, 'SomeMutation');
      expect(schema.subscriptionTypeName, 'SomeSubscription');
    });

    test('Default root operation type names', () {
      final schema = port.build('''
        type Query
        type Mutation
        type Subscription
      ''');
      expect(schema.queryTypeName, 'Query');
      expect(schema.mutationTypeName, 'Mutation');
      expect(schema.subscriptionTypeName, 'Subscription');
    });

    test('can build invalid schema', () {
      // Invalid, because it has no query root type; validateSchema
      // reports it from M3b.
      final schema = port.build('type Mutation');
      expect(schema.queryTypeName, isNull);
      expect(schema.mutationTypeName, 'Mutation');
    });

    test('Do not override standard types', () {
      // graphql-js ignores the definitions silently; they are GQL103 here,
      // and the built-ins stay.
      final result = port.buildResult('''
        scalar ID

        scalar __Schema
      ''');
      expect(port.codes(result), ['GQL103', 'GQL103']);
      expect(
        [for (final diagnostic in result.diagnostics) diagnostic.span?.text],
        ['ID', '__Schema'],
      );
      final partial = switch (result) {
        BuildFailure(:final partial) => partial,
        BuildSuccess() => fail('Redefined built-ins must fail.'),
      };
      expect(partial.typeNamed('ID'), same(builtIns.typeNamed('ID')));
      expect(
        partial.typeNamed('__Schema'),
        same(builtIns.typeNamed('__Schema')),
      );
    });

    test('Allows to reference introspection types', () {
      final schema = port.build('''
        type Query {
          introspectionField: __EnumValue
        }
      ''');
      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        query.fieldNamed('introspectionField')?.type,
        isA<NamedType>().having(
          (type) => type.name.value,
          'name',
          '__EnumValue',
        ),
      );
      expect(
        schema.typeNamed('__EnumValue'),
        same(builtIns.typeNamed('__EnumValue')),
      );
    });

    test('Allows to disable SDL validation', () {
      // Adapted: the builder never validates, so an unknown directive
      // builds without an option; schema validation (M3b) is what
      // `assumeValid` turns off.
      final schema = port.build('''
        type Query {
          foo: String @unknown
        }
      ''');
      final field = (schema.typeNamed('Query')! as ObjectType).fields.single;
      expect(field.appliedDirectives.single.name, 'unknown');
    });

    test('buildSchema parses directives on directive definitions', () {
      final schema = port.build(
        dedent('''
          type Query {
            foo: String
          }

          directive @bar @deprecated(reason: "Use another directive") on FIELD_DEFINITION
        '''),
      );
      expect(
        schema.directiveNamed('bar')?.deprecationReason,
        'Use another directive',
      );
    });

    test('Throws on unknown types', () {
      // References are names: the build succeeds and schema validation
      // reports the unknown type from M3b.
      final schema = port.build('''
        type Query {
          unknown: UnknownType
        }
      ''');
      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        port.printType(query),
        dedent('''
          type Query {
            unknown: UnknownType
          }
        '''),
      );
      expect(schema.typeNamed('UnknownType'), isNull);
    });

    test('correctly processes viral schema', () {
      final schema = port.build(
        dedent('''
          schema {
            query: Query
          }

          type Query {
            viruses: [Virus!]
          }

          type Virus {
            name: String!
            knownMutations: [Mutation!]!
          }

          type Mutation {
            name: String!
            geneSequence: String!
          }
        '''),
      );
      expect(schema.queryTypeName, 'Query');
      expect(schema.typeNamed('Virus')?.name, 'Virus');
      expect(schema.typeNamed('Mutation')?.name, 'Mutation');
      // The viral schema has a `Mutation` type, but no mutation root.
      expect(schema.mutationTypeName, isNull);
    });
  });
}
