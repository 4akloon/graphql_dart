import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// built-ins, directives, descriptions and type references. The built-in
// scalars, directives and introspection types are never listed in a
// schema; lookups find the shared instances of `BuiltIns`.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('Schema Builder', () {
    test('Ignores non-type system definitions', () {
      final result = port.buildResult('''
        type Query {
          str: String
        }

        fragment SomeFragment on Query {
          str
        }
      ''');
      expect(port.codes(result), ['GQL100']);
      expect(
        result.diagnostics.single.span?.text,
        startsWith('fragment SomeFragment on Query'),
      );
      // The types around the fragment still build.
      final partial = switch (result) {
        BuildFailure(:final partial) => partial,
        BuildSuccess() => fail('A fragment in SDL must fail.'),
      };
      expect(partial.typeNamed('Query'), isA<ObjectType>());
    });

    test('Match order of default types and directives', () {
      final built = switch (const SchemaBuilder().fromSdl(
        Document(const []),
      )) {
        BuildSuccess(:final schema) => schema,
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };
      final empty = Schema();
      expect(built.types, isEmpty);
      expect(built.directives, isEmpty);
      for (final directive in builtIns.directives) {
        expect(
          built.directiveNamed(directive.name),
          same(empty.directiveNamed(directive.name)),
        );
      }
    });

    test('Empty type', () {
      final sdl = dedent('''
        type EmptyType
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type', () {
      final sdl = dedent('''
        type Query {
          str: String
          int: Int
          float: Float
          id: ID
          bool: Boolean
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(schema.typeNamed(name), same(builtIns.scalarNamed(name)));
      }
    });

    test('include standard type only if it is used', () {
      final schema = port.build('type Query');
      expect([for (final type in schema.types) type.name], ['Query']);
      expect(port.print(schema), 'type Query');
    });

    test('With directives', () {
      final sdl = dedent('''
        directive @foo(arg: Int) on FIELD

        directive @repeatableFoo(arg: Int) repeatable on FIELD
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Supports descriptions', () {
      final sdl = dedent('''
        """Do you agree that this is the most creative schema ever?"""
        schema {
          query: Query
        }

        """This is a directive"""
        directive @foo(
          """It has an argument"""
          arg: Int
        ) on FIELD

        """Who knows what inside this scalar?"""
        scalar MysteryScalar

        """This is a input object type"""
        input FooInput {
          """It has a field"""
          field: Int
        }

        """This is a interface type"""
        interface Energy {
          """It also has a field"""
          str: String
        }

        """There is nothing inside!"""
        union BlackHole

        """With an enum"""
        enum Color {
          RED

          """Not a creative color"""
          GREEN
          BLUE
        }

        """What a great type"""
        type Query {
          """And a field to boot"""
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Maintains @include, @skip & @specifiedBy', () {
      final schema = port.build('type Query');
      expect(schema.directives, isEmpty);
      expect(builtIns.directives, hasLength(5));
      for (final name in [
        'skip',
        'include',
        'deprecated',
        'specifiedBy',
        'oneOf',
      ]) {
        expect(
          schema.directiveNamed(name),
          same(builtIns.directiveNamed(name)),
        );
      }
    });

    test('Overriding directives excludes specified', () {
      final result = port.buildResult('''
        directive @skip on FIELD
        directive @include on FIELD
        directive @deprecated on FIELD_DEFINITION
        directive @specifiedBy on FIELD_DEFINITION
        directive @oneOf on OBJECT
      ''');
      expect(port.codes(result), List.filled(5, 'GQL103'));
      expect(
        [for (final diagnostic in result.diagnostics) diagnostic.span?.text],
        ['skip', 'include', 'deprecated', 'specifiedBy', 'oneOf'],
      );
      // The built-ins stay, and none of the redefinitions is kept.
      final partial = switch (result) {
        BuildFailure(:final partial) => partial,
        BuildSuccess() => fail('Redefined built-ins must fail.'),
      };
      expect(partial.directives, isEmpty);
      expect(
        partial.directiveNamed('skip'),
        same(builtIns.directiveNamed('skip')),
      );
    });

    test(
      'Adding directives maintains @include, @skip, @deprecated, @specifiedBy, and @oneOf',
      () {
        final schema = port.build('''
          directive @foo(arg: Int) on FIELD
        ''');
        expect(
          [
            for (final directive in schema.directives) directive.name,
          ],
          ['foo'],
        );
        for (final name in [
          'skip',
          'include',
          'deprecated',
          'specifiedBy',
          'oneOf',
        ]) {
          expect(schema.directiveNamed(name), isNotNull);
        }
      },
    );

    test('Type modifiers', () {
      final sdl = dedent('''
        type Query {
          nonNullStr: String!
          listOfStrings: [String]
          listOfNonNullStrings: [String!]
          nonNullListOfStrings: [String]!
          nonNullListOfNonNullStrings: [String!]!
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Recursive type', () {
      final sdl = dedent('''
        type Query {
          str: String
          recurse: Query
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Two types circular', () {
      final sdl = dedent('''
        type TypeOne {
          str: String
          typeTwo: TypeTwo
        }

        type TypeTwo {
          str: String
          typeOne: TypeOne
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Single argument field', () {
      final sdl = dedent('''
        type Query {
          str(int: Int): String
          floatToStr(float: Float): String
          idToStr(id: ID): String
          booleanToStr(bool: Boolean): String
          strToStr(bool: String): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with multiple arguments', () {
      final sdl = dedent('''
        type Query {
          str(int: Int, bool: Boolean): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
