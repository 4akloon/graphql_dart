import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// each kind of type and the root operation types, built and printed.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Schema Builder', () {
    test('Empty interface', () {
      final sdl = dedent('''
        interface EmptyInterface
      ''');
      // graphql-js leaves `interfaces` undefined; the Dart node has an
      // empty list.
      final [definition] = port.document(sdl).definitions;
      expect(
        definition,
        isA<InterfaceTypeDefinition>().having(
          (definition) => definition.interfaces,
          'interfaces',
          isEmpty,
        ),
      );
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with interface', () {
      final sdl = dedent('''
        type Query implements WorldInterface {
          str: String
        }

        interface WorldInterface {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple interface hierarchy', () {
      final sdl = dedent('''
        schema {
          query: Child
        }

        interface Child implements Parent {
          str: String
        }

        type Hello implements Parent & Child {
          str: String
        }

        interface Parent {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty enum', () {
      final sdl = dedent('''
        enum EmptyEnum
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple output enum', () {
      final sdl = dedent('''
        enum Hello {
          WORLD
        }

        type Query {
          hello: Hello
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple input enum', () {
      final sdl = dedent('''
        enum Hello {
          WORLD
        }

        type Query {
          str(hello: Hello): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Multiple value enum', () {
      final sdl = dedent('''
        enum Hello {
          WO
          RLD
        }

        type Query {
          hello: Hello
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty union', () {
      final sdl = dedent('''
        union EmptyUnion
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple Union', () {
      final sdl = dedent('''
        union Hello = World

        type Query {
          hello: Hello
        }

        type World {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Multiple Union', () {
      final sdl = dedent('''
        union Hello = WorldOne | WorldTwo

        type Query {
          hello: Hello
        }

        type WorldOne {
          str: String
        }

        type WorldTwo {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Can build recursive Union', () {
      final schema = port.build('''
        union Hello = Hello

        type Query {
          hello: Hello
        }
      ''');
      // graphql-js then checks that validateSchema reports the union;
      // schema validation arrives in M3b.
      final hello = schema.typeNamed('Hello');
      expect(hello, isA<UnionType>());
      expect(port.print(Schema(types: [?hello])), 'union Hello = Hello');
    });

    test('Custom Scalar', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          customScalar: CustomScalar
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty Input Object', () {
      final sdl = dedent('''
        input EmptyInputObject
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple Input Object', () {
      final sdl = dedent('''
        input Input {
          int: Int
        }

        type Query {
          field(in: Input): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple argument field with default', () {
      final sdl = dedent('''
        type Query {
          str(int: Int = 2): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Custom scalar argument field with default', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          str(int: CustomScalar = 2): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with mutation', () {
      final sdl = dedent('''
        schema {
          query: HelloScalars
          mutation: Mutation
        }

        type HelloScalars {
          str: String
          int: Int
          bool: Boolean
        }

        type Mutation {
          addHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with subscription', () {
      final sdl = dedent('''
        schema {
          query: HelloScalars
          subscription: Subscription
        }

        type HelloScalars {
          str: String
          int: Int
          bool: Boolean
        }

        type Subscription {
          subscribeHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced type implementing referenced interface', () {
      final sdl = dedent('''
        type Concrete implements Interface {
          key: String
        }

        interface Interface {
          key: String
        }

        type Query {
          interface: Interface
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced interface implementing referenced interface', () {
      final sdl = dedent('''
        interface Child implements Parent {
          key: String
        }

        interface Parent {
          key: String
        }

        type Query {
          interfaceField: Parent
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced type implementing referenced union', () {
      final sdl = dedent('''
        type Concrete {
          key: String
        }

        type Query {
          union: Union
        }

        union Union = Concrete
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
