import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// redefinitions, root operation types and directive extensions. The model
// keeps no extension nodes, so their checks are dropped.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('Throws on unknown types', () {
      // References are names: the build succeeds and schema validation
      // reports the unknown type from M3b.
      final extendedSchema = port.extend(Schema(), '''
        type Query {
          unknown: UnknownType
        }
      ''');
      expect(extendedSchema.typeNamed('Query'), isA<ObjectType>());
      expect(extendedSchema.typeNamed('UnknownType'), isNull);
    });

    test('does not allow replacing a default directive', () {
      final result = port.extendResult(Schema(), '''
        directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD
      ''');
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.message),
        ['The built-in directive "@include" cannot be redefined.'],
      );
      expect(port.codes(result), ['GQL103']);
      expect(result.diagnostics.single.span?.text, 'include');
    });

    test('does not allow replacing an existing enum value', () {
      final schema = port.build('''
        enum SomeEnum {
          ONE
        }
      ''');
      final result = port.extendResult(schema, '''
        extend enum SomeEnum {
          ONE
        }
      ''');
      expect(result.diagnostics.map((diagnostic) => diagnostic.message), [
        'Enum value "SomeEnum.ONE" already exists in the schema. '
            'It cannot also be defined in this type extension.',
      ]);
      expect(port.codes(result), ['GQL106']);
      expect(result.diagnostics.single.span?.text, 'ONE');
    });

    group('can add additional root operation types', () {
      test('does not automatically include common root type names', () {
        final extendedSchema = port.extend(Schema(), 'type Mutation');
        expect(extendedSchema.typeNamed('Mutation'), isNotNull);
        expect(extendedSchema.mutationTypeName, isNull);
      });

      test('adds schema definition missing in the original schema', () {
        final schema = port.build('''
          directive @foo on SCHEMA
          type Foo
        ''');
        expect(schema.queryTypeName, isNull);

        final extensionSdl = dedent('''
          schema @foo {
            query: Foo
          }
        ''');
        final extendedSchema = port.extend(schema, extensionSdl);
        expect(extendedSchema.queryTypeName, 'Foo');
        expect(extendedSchema.span?.text, extensionSdl);
      });

      test('adds new root types via schema extension', () {
        final schema = port.build('''
          type Query
          type MutationRoot
        ''');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: MutationRoot
          }
        ''');
        expect(extendedSchema.mutationTypeName, 'MutationRoot');
      });

      test('adds directive via schema extension', () {
        final schema = port.build('''
          type Query

          directive @foo on SCHEMA
        ''');
        final extendedSchema = port.extend(schema, 'extend schema @foo');
        expect(
          [
            for (final directive in extendedSchema.appliedDirectives)
              directive.name,
          ],
          ['foo'],
        );
      });

      test('adds multiple new root types via schema extension', () {
        final schema = port.build('type Query');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
            subscription: Subscription
          }

          type Mutation
          type Subscription
        ''');
        expect(extendedSchema.mutationTypeName, 'Mutation');
        expect(extendedSchema.subscriptionTypeName, 'Subscription');
      });

      test('applies multiple schema extensions', () {
        final schema = port.build('type Query');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
          }
          type Mutation

          extend schema {
            subscription: Subscription
          }
          type Subscription
        ''');
        expect(extendedSchema.mutationTypeName, 'Mutation');
        expect(extendedSchema.subscriptionTypeName, 'Subscription');
      });

      test('schema extension AST are available from schema object', () {
        final schema = port.build('''
          type Query

          directive @foo on SCHEMA
        ''');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
          }
          type Mutation

          extend schema {
            subscription: Subscription
          }
          type Subscription
        ''');
        final extendedTwiceSchema = port.extend(
          extendedSchema,
          'extend schema @foo',
        );
        // What the extensions added stays; the nodes are not kept.
        expect(extendedTwiceSchema.mutationTypeName, 'Mutation');
        expect(extendedTwiceSchema.subscriptionTypeName, 'Subscription');
        expect(
          [
            for (final directive in extendedTwiceSchema.appliedDirectives)
              directive.name,
          ],
          ['foo'],
        );
      });

      test('extend directive to make it deprecated', () {
        final schema = port.build(
          'directive @isDeprecated on FIELD_DEFINITION',
        );
        final extendedSchema = port.extend(schema, '''
          extend directive @isDeprecated @deprecated(reason: "use another directive")
        ''');
        expect(
          extendedSchema.directiveNamed('isDeprecated')?.deprecationReason,
          'use another directive',
        );
      });

      test('preserves deprecated directives when extending other types', () {
        final schema = port.build(
          dedent('''
            type Query {
              foo: String
            }

            directive @isDeprecated @deprecated(reason: "use another directive") on FIELD_DEFINITION
          '''),
        );
        final extendedSchema = port.extend(
          schema,
          dedent('''
            extend type Query {
              bar: Int
            }
          '''),
        );
        expect(
          extendedSchema.directiveNamed('isDeprecated')?.deprecationReason,
          'use another directive',
        );
      });

      test('applies directive extensions defined in the same document', () {
        final schema = port.build(
          dedent('''
            directive @onDirective on DIRECTIVE_DEFINITION
            directive @someDirective on FIELD_DEFINITION

            extend directive @someDirective @onDirective
          '''),
        );
        final someDirective = schema.directiveNamed('someDirective');
        expect(
          [
            for (final directive in [...?someDirective?.appliedDirectives])
              directive.name,
          ],
          ['onDirective'],
        );
      });

      test('builds directives with deprecation from extensions', () {
        final extendedSchema = port.extend(
          Schema(),
          dedent('''
            directive @isDeprecated on FIELD_DEFINITION

            extend directive @isDeprecated @deprecated(reason: "use another directive")
          '''),
        );
        final isDeprecated = extendedSchema.directiveNamed('isDeprecated');
        expect(isDeprecated?.deprecationReason, 'use another directive');
        expect(
          isDeprecated?.span?.text,
          'directive @isDeprecated on FIELD_DEFINITION',
        );
      });

      test(
        'applies multiple directive extensions defined in the same document',
        () {
          final schema = port.build(
            dedent('''
              directive @onDirective on DIRECTIVE_DEFINITION
              directive @otherDirective on DIRECTIVE_DEFINITION
              directive @someDirective on FIELD_DEFINITION

              extend directive @someDirective @onDirective
              extend directive @someDirective @otherDirective
            '''),
          );
          final someDirective = schema.directiveNamed('someDirective');
          expect(
            [
              for (final directive in [...?someDirective?.appliedDirectives])
                directive.name,
            ],
            ['onDirective', 'otherDirective'],
          );
        },
      );

      test('extend directive without adding new directives is an error', () {
        const parser = Parser(
          options: ParserOptions(allowDirectiveExtensions: true),
        );
        final result = parser.parse(Source('extend directive @isDeprecated'));
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.message),
          ['Unexpected <EOF>.'],
        );
      });
    });
  });
}
