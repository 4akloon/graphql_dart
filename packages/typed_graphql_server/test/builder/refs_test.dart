import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  String print(TypeRef typeRef) => const Printer().print(typeRef);

  group('output refs', () {
    test('a built-in scalar is non-null', () {
      expect(print(b.string.typeRef), 'String!');
    });

    test('nullable drops the non-null wrapper', () {
      expect(print(b.int.nullable.typeRef), 'Int');
    });

    test('a list is non-null around its item', () {
      expect(print(b.list(b.int).typeRef), '[Int!]!');
    });

    test('a nullable list of nullable items', () {
      expect(print(b.list(b.int.nullable).nullable.typeRef), '[Int]');
    });

    test('the named type is found through wrappers', () {
      expect(b.list(b.boolean).namedType.name, 'Boolean');
    });

    test('nullable of nullable is the same ref', () {
      final once = b.id.nullable;
      expect(once.nullable, same(once));
    });
  });

  group('input refs', () {
    test('an input list prints like an output list', () {
      expect(print(b.inputList(b.float).typeRef), '[Float!]!');
    });

    test('adapt gives a real List<int>', () {
      final adapted = b.inputList(b.int).adapt(<Object?>[1, 2]);
      expect(adapted, isA<List<int>>());
      expect(adapted, [1, 2]);
    });

    test('adapt keeps null in a nullable item list', () {
      final adapted = b.inputList(b.int.nullable).adapt(<Object?>[1, null]);
      expect(adapted, isA<List<int?>>());
      expect(adapted, [1, null]);
    });

    test('adapt of a nullable ref gives null for null', () {
      expect(b.string.nullable.adapt(null), isNull);
    });

    test('jsonOf writes a leaf through its codec', () {
      expect(b.int.jsonOf(3), JsonNumber(3));
    });

    test('jsonOf writes a list as an array and null as JsonNull', () {
      expect(
        b.inputList(b.string.nullable).jsonOf(['a', null]),
        JsonArray([const JsonString('a'), const JsonNull()]),
      );
    });

    test('jsonOf of a value the codec cannot write is an ArgumentError', () {
      expect(() => b.int.jsonOf(1 << 40), throwsArgumentError);
    });
  });

  group('scalars', () {
    test('a custom scalar keeps its codec and url', () {
      final date = b.scalar<String>(
        'Date',
        const StringCodec(),
        description: 'A day.',
        specifiedByUrl: 'https://example.com/date',
      );
      expect(date.name, 'Date');
      expect(date.description, 'A day.');
      expect(date.specifiedByUrl, 'https://example.com/date');
      expect(print(date.typeRef), 'Date!');
    });

    test('built-in scalars are not declared types', () {
      final fresh = ExecutableSchemaBuilder<Object?>();
      fresh.scalar<String>('Date', const StringCodec());
      expect(fresh.definitions.map((d) => d.name), ['Date']);
    });

    test('a builder has one instance of each built-in scalar', () {
      expect(b.int, same(b.int));
      expect(b.int.name, 'Int');
      expect(b.float.name, 'Float');
      expect(b.boolean.name, 'Boolean');
      expect(b.id.name, 'ID');
    });
  });
}
