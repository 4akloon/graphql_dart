import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the schemas with directives, deprecation, `@specifiedBy` and `@oneOf`.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    test('builds a schema with custom directives', () {
      final sdl = dedent('''
        """This is a custom directive"""
        directive @customDirective repeatable on FIELD

        type Query {
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // Directive deprecation is working-draft: the SDL applies @deprecated
    // to the definition and the query asks for it.
    test('builds a schema with deprecated directives', () {
      final introspection = port.introspectionOf(
        '''
type Query {
  string: String
}

directive @someDirective @deprecated(reason: "Use another directive") on QUERY
''',
        const IntrospectionQuery(includesDirectiveDeprecation: true),
      );
      final directive = port
          .client(introspection)
          .directiveNamed(
            'someDirective',
          );
      expect(directive?.name, 'someDirective');
      expect(directive?.deprecationReason, 'Use another directive');
    });

    // Built-ins are not listed in `Schema.directives`: the port checks the
    // server's result lists directives before it removes them.
    test('builds a schema without directives', () {
      final sdl = dedent('''
        type Query {
          string: String
        }
      ''');
      final introspection = port.introspectionOf(sdl);
      final schema = port.schemaIn(introspection);
      expect(schema['directives'], isNotEmpty);
      schema.remove('directives');
      final client = port.client(introspection);
      expect(client.directives, isEmpty);
      expect(schemas.print(client), sdl);
    });

    test('builds a schema aware of deprecation', () {
      final sdl = dedent('''
        directive @someDirective(
          """This is a shiny new argument"""
          shinyArg: SomeInputObject

          """This was our design mistake :("""
          oldArg: String @deprecated(reason: "Use shinyArg")
        ) on QUERY

        enum Color {
          """So rosy"""
          RED

          """So grassy"""
          GREEN

          """So calming"""
          BLUE

          """So sickening"""
          MAUVE @deprecated(reason: "No longer in fashion")
        }

        input SomeInputObject {
          """Nothing special about it, just deprecated for some unknown reason"""
          oldField: String @deprecated(reason: "Don't use it, use newField instead!")

          """Same field but with a new name"""
          newField: String
        }

        type Query {
          """This is a shiny string field"""
          shinyString: String

          """This is a deprecated string field"""
          deprecatedString: String @deprecated(reason: "Use shinyString")

          """Color of a week"""
          color: Color

          """Some random field"""
          someField(
            """This is a shiny new argument"""
            shinyArg: SomeInputObject

            """This was our design mistake :("""
            oldArg: String @deprecated(reason: "Use shinyArg")
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with empty deprecation reasons', () {
      final sdl = dedent('''
        directive @someDirective(someArg: SomeInputObject @deprecated(reason: "")) on QUERY

        type Query {
          someField(someArg: SomeInputObject @deprecated(reason: "")): SomeEnum @deprecated(reason: "")
        }

        input SomeInputObject {
          someInputField: String @deprecated(reason: "")
        }

        enum SomeEnum {
          SOME_VALUE @deprecated(reason: "")
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with specifiedBy url', () {
      final sdl = dedent('''
        scalar Foo @specifiedBy(url: "https://example.com/foo_spec")

        type Query {
          foo: Foo
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with @oneOf directive', () {
      final sdl = dedent('''
        type Query {
          someField(someArg: SomeInputObject): String
        }

        input SomeInputObject @oneOf {
          someInputField1: String
          someInputField2: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // `assumeValid` has no counterpart: the client schema builds, and
    // the validator reports what is wrong with it.
    test('can build invalid schema', () {
      final introspection = schemas.build('type Query').toIntrospection();
      final client = port.client(introspection);
      expect(schemas.validationErrors(client), [
        'GQL125 Type Query must define one or more fields.',
      ]);
    });
  });
}
