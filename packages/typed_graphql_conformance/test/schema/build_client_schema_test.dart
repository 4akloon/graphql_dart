import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the schemas it builds. graphql-js builds some schemas in code; the port
// writes them as SDL. Execution arrives in M5, so the two execution tests
// are skipped.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    test('builds a simple schema', () {
      final sdl = dedent('''
        """Simple schema"""
        schema {
          query: Simple
        }

        """This is a simple type"""
        type Simple {
          """This is a string field"""
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema without the query type', () {
      final sdl = dedent('''
        type Query {
          foo: String
        }
      ''');
      final introspection = port.introspectionOf(sdl);
      port.schemaIn(introspection).remove('queryType');
      final client = port.client(introspection);
      expect(client.queryTypeName, isNull);
      expect(schemas.print(client), sdl);
    });

    test('builds a simple schema with all operation types', () {
      final sdl = dedent('''
        schema {
          query: QueryType
          mutation: MutationType
          subscription: SubscriptionType
        }

        """This is a simple mutation type"""
        type MutationType {
          """Set the string field"""
          string: String
        }

        """This is a simple query type"""
        type QueryType {
          """This is a string field"""
          string: String
        }

        """This is a simple subscription type"""
        type SubscriptionType {
          """This is a string field"""
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // A built-in is found through `typeNamed`, so "used" is identity with
    // the shared `BuiltIns` instance.
    test('uses built-in scalars when possible', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          int: Int
          float: Float
          string: String
          boolean: Boolean
          id: ID
          custom: CustomScalar
        }
      ''');
      expect(port.cycle(sdl), sdl);
      final schema = schemas.build(sdl);
      final client = port.client(schema.toIntrospection());
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(client.typeNamed(name), same(const BuiltIns().typeNamed(name)));
      }
      expect(
        client.typeNamed('CustomScalar'),
        isNot(same(schema.typeNamed('CustomScalar'))),
      );
    });

    // Built-ins are found, not listed (M3a decision 2): the port checks
    // that the result lists no unused scalar and that the client schema
    // declares none.
    test('includes standard types only if they are used', () {
      final introspection = port.introspectionOf('type Query { foo: String }');
      final names = [
        for (final type in port.schemaIn(introspection)['types']! as List)
          (type! as Map<String, Object?>)['name'],
      ];
      expect(names, isNot(contains('Int')));
      expect(names, isNot(contains('Float')));
      expect(names, isNot(contains('ID')));
      final client = port.client(introspection);
      expect(client.types.map((type) => type.name), ['Query']);
    });

    test('builds a schema with a recursive type reference', () {
      final sdl = dedent('''
        schema {
          query: Recur
        }

        type Recur {
          recur: Recur
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with a circular type reference', () {
      final sdl = dedent('''
        type Dog {
          bestFriend: Human
        }

        type Human {
          bestFriend: Dog
        }

        type Query {
          dog: Dog
          human: Human
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an interface', () {
      final sdl = dedent('''
        type Dog implements Friendly {
          bestFriend: Friendly
        }

        interface Friendly {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
        }

        type Human implements Friendly {
          bestFriend: Friendly
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an interface hierarchy', () {
      final sdl = dedent('''
        type Dog implements Friendly & Named {
          bestFriend: Friendly
          name: String
        }

        interface Friendly implements Named {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
          name: String
        }

        type Human implements Friendly & Named {
          bestFriend: Friendly
          name: String
        }

        interface Named {
          name: String
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an implicit interface', () {
      final sdl = dedent('''
        type Dog implements Friendly {
          bestFriend: Friendly
        }

        interface Friendly {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
        }

        type Query {
          dog: Dog
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with a union', () {
      final sdl = dedent('''
        type Dog {
          bestFriend: Friendly
        }

        union Friendly = Dog | Human

        type Human {
          bestFriend: Friendly
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with complex field values', () {
      final sdl = dedent('''
        type Query {
          string: String
          listOfString: [String]
          nonNullString: String!
          nonNullListOfString: [String]!
          nonNullListOfNonNullString: [String!]!
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with field arguments', () {
      final sdl = dedent('''
        type Query {
          """A field with a single arg"""
          one(
            """This is an int arg"""
            intArg: Int
          ): String

          """A field with a two args"""
          two(
            """This is a list of int arg"""
            listArg: [Int]

            """This is a required arg"""
            requiredArg: Boolean!
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with default value on custom scalar field', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          testField(testArg: CustomScalar = "default"): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // graphql-js gives the server values integers; the model has no
    // internal values, so the port checks names, descriptions and
    // deprecation, as graphql-js does for the client.
    test('builds a schema with an enum', () {
      final introspection = schemas.build('''
"""Varieties of food stuffs"""
enum Food {
  """Foods that are vegetables."""
  VEGETABLES
  FRUITS
  OILS @deprecated(reason: "Too fatty")
}

type EnumFields {
  """Repeats the arg you give it"""
  food("""what kind of food?""" kind: Food): Food
}

schema {
  query: EnumFields
}
''').toIntrospection();
      final client = port.client(introspection);
      expect(client.toIntrospection(), introspection);
      final values = schemas.assertType<EnumType>(client, 'Food').values;
      expect(values, hasLength(3));
      expect(
        [
          for (final value in values)
            (value.name, value.description, value.deprecationReason),
        ],
        [
          ('VEGETABLES', 'Foods that are vegetables.', null),
          ('FRUITS', null, null),
          ('OILS', null, 'Too fatty'),
        ],
      );
    });

    test('builds a schema with an input object', () {
      final sdl = dedent('''
        """An input address"""
        input Address {
          """What street is this address?"""
          street: String!

          """The city the address is within?"""
          city: String!

          """The country (blank will assume USA)."""
          country: String = "USA"
        }

        type Query {
          """Get a geocode from an address"""
          geocode(
            """The address to lookup"""
            address: Address
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with field arguments with default values', () {
      final sdl = dedent('''
        input Geo {
          lat: Float
          lon: Float
        }

        type Query {
          defaultID(intArg: ID = "123"): String
          defaultInt(intArg: Int = 30): String
          defaultList(listArg: [Int] = [1, 2, 3]): String
          defaultObject(objArg: Geo = { lat: 37.485, lon: -122.148 }): String
          defaultNull(intArg: Int = null): String
          noDefault(intArg: Int): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
