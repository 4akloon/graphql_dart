import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/config/dart_reference.dart';
import 'package:typed_graphql_codegen/src/config/scalar_mapping.dart';
import 'package:typed_graphql_codegen/src/emit/dart_type.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

const _sdl = '''
type Query { a: Int }
type User { name: String }
interface Node { id: ID }
union Result = User
enum Role { ADMIN }
input Filter { name: String }
scalar Date
scalar Money
scalar Blob
''';

void main() {
  Schema schema() {
    final document = const Parser().parse(Source(_sdl)).requireDocument();
    return (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
  }

  TypeRef type(String text) {
    final document = const Parser()
        .parse(Source('type Probe { f: $text }'))
        .requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    return (schema.typeNamed('Probe')! as ObjectType).fields.first.type;
  }

  final TypeMapper mapper = TypeMapper(schema(), const {
    'Date': ScalarMapping(
      DartReference(null, 'DateTime'),
      DartReference('package:a/codecs.dart', 'DateTimeCodec'),
    ),
    'Money': ScalarMapping(
      DartReference('package:a/money.dart', 'Money'),
      DartReference('package:a/money.dart', 'MoneyCodec'),
    ),
  });

  final builtIns = <String, DartType>{
    'String': const DartType(
      'String',
      'client.ScalarDataCodec(graphql.StringCodec())',
    ),
    'ID': const DartType('String', 'client.ScalarDataCodec(graphql.IdCodec())'),
    'Int': const DartType('int', 'client.ScalarDataCodec(graphql.IntCodec())'),
    'Float': const DartType(
      'double',
      'client.ScalarDataCodec(graphql.FloatCodec())',
    ),
    'Boolean': const DartType(
      'bool',
      'client.ScalarDataCodec(graphql.BooleanCodec())',
    ),
  };
  builtIns.forEach((name, expected) {
    test('$name maps to its built-in codec', () {
      expect(mapper.named(name, Imports()), expected);
    });
  });

  test('a mapped scalar of dart:core needs no prefix for its type', () {
    final Imports imports = Imports();
    expect(
      mapper.named('Date', imports),
      const DartType(
        'DateTime',
        'client.ScalarDataCodec(scalar_0.DateTimeCodec())',
      ),
    );
  });

  test('a mapped scalar of a package is prefixed and imported', () {
    final Imports imports = Imports();
    expect(
      mapper.named('Money', imports),
      const DartType(
        'scalar_0.Money',
        'client.ScalarDataCodec(scalar_0.MoneyCodec())',
      ),
    );
    expect(imports.prefixFor('package:a/money.dart'), 'scalar_0');
  });

  test('an unmapped custom scalar is a JsonValue', () {
    expect(
      mapper.named('Blob', Imports()),
      const DartType('graphql.JsonValue', 'client.JsonDataCodec()'),
    );
  });

  test('an enum maps to its class and codec', () {
    expect(
      mapper.named('Role', Imports()),
      const DartType('Role', 'Role.codec'),
    );
  });

  test('an input object maps to its class and codec', () {
    expect(
      mapper.named('Filter', Imports()),
      const DartType('Filter', 'Filter.codec'),
    );
  });

  test('an object maps to the class the caller chose', () {
    expect(
      mapper.named('User', Imports(), objectClass: 'GetUserUser'),
      const DartType('GetUserUser', 'GetUserUser.codec'),
    );
  });

  test('an object without objectClass is an ArgumentError', () {
    expect(
      () => mapper.named('User', Imports()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an unknown type is an ArgumentError', () {
    expect(
      () => mapper.named('Nope', Imports()),
      throwsA(isA<ArgumentError>()),
    );
  });

  const string = 'client.ScalarDataCodec(graphql.StringCodec())';

  test('[String!]! has no nullable level', () {
    expect(
      mapper.of(type('[String!]!'), Imports()),
      const DartType('List<String>', 'client.ListDataCodec($string)'),
    );
  });

  test('[String] is nullable in its items and as a whole', () {
    expect(
      mapper.of(type('[String]'), Imports()),
      const DartType(
        'List<String?>?',
        'client.NullableDataCodec(client.ListDataCodec('
            'client.NullableDataCodec($string)))',
      ),
    );
  });

  test('[[Int!]]! nests lists', () {
    const int_ = 'client.ScalarDataCodec(graphql.IntCodec())';
    expect(
      mapper.of(type('[[Int!]]!'), Imports()),
      const DartType(
        'List<List<int>?>',
        'client.ListDataCodec(client.NullableDataCodec('
            'client.ListDataCodec($int_)))',
      ),
    );
  });

  test('ofNonNull removes the outermost nullability only', () {
    expect(
      mapper.ofNonNull(type('[String]'), Imports()),
      const DartType(
        'List<String?>',
        'client.ListDataCodec(client.NullableDataCodec($string))',
      ),
    );
  });

  test('ofNonNull keeps a non-null type non-null', () {
    expect(
      mapper.ofNonNull(type('String!'), Imports()),
      const DartType('String', string),
    );
  });

  test('a list nested 200 levels deep maps', () {
    TypeRef nested = const NamedType(Name('String'));
    for (int depth = 0; depth < 200; depth++) {
      nested = ListType(nested);
    }
    final DartType type = mapper.of(nested, Imports());
    expect(type.type, '${'List<' * 200}String?${'>?' * 200}');
  });
}
