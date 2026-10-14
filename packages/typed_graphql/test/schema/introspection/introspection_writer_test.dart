import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  Map<String, Object?> schemaOf(
    String sdl, [
    IntrospectionQuery query = IntrospectionQuery.full,
  ]) {
    final json = Built(sdl).schema.toIntrospection(query).toJson();
    return json['__schema']! as Map<String, Object?>;
  }

  List<Map<String, Object?>> listOf(Object? json) =>
      (json! as List<Object?>).cast<Map<String, Object?>>();

  Map<String, Object?> typeOf(Map<String, Object?> schema, String name) =>
      listOf(schema['types']).singleWhere((type) => type['name'] == name);

  Map<String, Object?> fieldOf(Map<String, Object?> type, String name) =>
      listOf(type['fields']).singleWhere((field) => field['name'] == name);

  List<Object?> namesOf(Object? json) => [
    for (final element in listOf(json)) element['name'],
  ];

  group('Schema.toIntrospection', () {
    test('writes the root types by name and kind', () {
      final schema = schemaOf('type Query { a: String }');
      expect(schema['queryType'], {'name': 'Query', 'kind': 'OBJECT'});
      expect(schema['mutationType'], isNull);
      expect(schema['subscriptionType'], isNull);
    });

    test('lists declared types, used built-in scalars, then introspection', () {
      final schema = schemaOf('type Query { a: Int }');
      expect(namesOf(schema['types']), [
        'Query',
        'String',
        'Int',
        'Boolean',
        '__Schema',
        '__Type',
        '__TypeKind',
        '__Field',
        '__InputValue',
        '__EnumValue',
        '__Directive',
        '__DirectiveLocation',
      ]);
    });

    test('lists declared directives before the built-in ones', () {
      final schema = schemaOf('directive @a on FIELD type Query { a: Int }');
      expect(namesOf(schema['directives']), [
        'a',
        'include',
        'skip',
        'deprecated',
        'specifiedBy',
        'oneOf',
      ]);
    });

    test('lists @defer and @stream when the schema has them', () {
      final document = Sdl('type Query { a: Int }').document;
      final result = const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(document);
      final schema = (result as BuildSuccess).schema;
      final json = schema.toIntrospection().toJson()['__schema']!;
      expect(
        namesOf((json as Map<String, Object?>)['directives']),
        containsAllInOrder(['oneOf', 'defer', 'stream']),
      );
    });

    test('writes wrappers as nested ofType levels', () {
      final type = typeOf(schemaOf('type Query { a: [Int!]! }'), 'Query');
      final reference = fieldOf(type, 'a')['type']! as Map<String, Object?>;
      expect(reference['kind'], 'NON_NULL');
      expect(reference['name'], isNull);
      final list = reference['ofType']! as Map<String, Object?>;
      final item = list['ofType']! as Map<String, Object?>;
      expect(item['ofType'], {'kind': 'SCALAR', 'name': 'Int', 'ofType': null});
    });

    test('cuts a reference at the type depth', () {
      final schema = schemaOf(
        'type Query { a: [Int!]! }',
        const IntrospectionQuery(typeDepth: 1),
      );
      final type = typeOf(schema, 'Query');
      expect(fieldOf(type, 'a')['type'], {
        'kind': 'NON_NULL',
        'name': null,
        'ofType': {'kind': 'LIST', 'name': null},
      });
    });

    test('writes the schema description when the query reads it', () {
      final schema = schemaOf('''
        "The saga." schema { query: Query }
        type Query { a: Int }
      ''');
      expect(schema['description'], 'The saga.');
    });

    test('rejects a type depth below zero', () {
      expect(
        () => schemaOf(
          'type Query { a: Int }',
          const IntrospectionQuery(typeDepth: -1),
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects a type depth above 100', () {
      expect(
        () => schemaOf(
          'type Query { a: Int }',
          const IntrospectionQuery(typeDepth: 101),
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('writes a deep reference without recursion', () {
      TypeRef type = const NamedType(Name('Int'));
      for (var i = 0; i < 10000; i++) {
        type = ListType(type);
      }
      final schema = Schema(
        types: [
          ObjectType('Query', fields: [SchemaField('a', type)]),
        ],
        queryTypeName: 'Query',
      );
      final json = schema.toIntrospection(
        const IntrospectionQuery(typeDepth: 100),
      );
      final schemaJson = json.toJson()['__schema']! as Map<String, Object?>;
      var hops = 0;
      var reference =
          fieldOf(typeOf(schemaJson, 'Query'), 'a')['type']!
              as Map<String, Object?>;
      while (reference.containsKey('ofType')) {
        reference = reference['ofType']! as Map<String, Object?>;
        hops++;
      }
      // The 101st level is the last the query reads, and has no ofType.
      expect(hops, 100);
      expect(reference['kind'], 'LIST');
    });

    test('prints default values as GraphQL', () {
      final type = typeOf(
        schemaOf('type Query { a(b: [Int] = [1, 2]): Int }'),
        'Query',
      );
      final argument = listOf(fieldOf(type, 'a')['args']).single;
      expect(argument['defaultValue'], '[1, 2]');
    });

    test('leaves deprecated arguments out unless the query reads them', () {
      const sdl = 'type Query { a(b: Int @deprecated, c: Int): Int }';
      final full = typeOf(schemaOf(sdl), 'Query');
      expect(namesOf(fieldOf(full, 'a')['args']), ['b', 'c']);
      final older = typeOf(schemaOf(sdl, const IntrospectionQuery()), 'Query');
      expect(namesOf(fieldOf(older, 'a')['args']), ['c']);
    });

    test('writes the possible types of interfaces and unions', () {
      final schema = schemaOf('''
        type Query { a: I, b: U }
        interface I { a: Int }
        type A implements I { a: Int }
        union U = A
      ''');
      expect(namesOf(typeOf(schema, 'I')['possibleTypes']), ['A']);
      expect(namesOf(typeOf(schema, 'U')['possibleTypes']), ['A']);
      expect(namesOf(typeOf(schema, 'A')['interfaces']), ['I']);
      expect(typeOf(schema, 'A')['possibleTypes'], isNull);
    });

    test('writes every union member, also one that is not an object', () {
      final schema = schemaOf('''
        type Query { a: U }
        interface I { a: Int }
        type A { a: Int }
        union U = A | I
      ''');
      expect(namesOf(typeOf(schema, 'U')['possibleTypes']), ['A', 'I']);
    });

    test('writes only the fields the query reads', () {
      final schema = schemaOf(
        '"Q" type Query { a: Int }',
        const IntrospectionQuery(includesDescriptions: false),
      );
      expect(schema.containsKey('description'), isFalse);
      expect(typeOf(schema, 'Query').keys, [
        'kind',
        'name',
        'fields',
        'inputFields',
        'interfaces',
        'enumValues',
        'possibleTypes',
      ]);
    });

    test('writes directive deprecation only when the query reads it', () {
      final directive = SchemaDirective(
        'old',
        locations: [DirectiveLocation.query],
        appliedDirectives: [
          AppliedDirective(
            'deprecated',
            arguments: [
              const Argument(Name('reason'), StringValue('Use another')),
            ],
          ),
        ],
      );
      final schema = Schema(directives: [directive]);
      Map<String, Object?> writtenWith(IntrospectionQuery query) {
        final json = schema.toIntrospection(query).toJson()['__schema']!;
        return listOf((json as Map<String, Object?>)['directives']).first;
      }

      expect(
        writtenWith(IntrospectionQuery.full),
        isNot(contains('isDeprecated')),
      );
      expect(
        writtenWith(
          const IntrospectionQuery(includesDirectiveDeprecation: true),
        ),
        containsPair('deprecationReason', 'Use another'),
      );
    });

    test('rejects a reference to a type the schema lacks', () {
      expect(
        () => Built('type Query { a: Missing }').schema.toIntrospection(),
        throwsArgumentError,
      );
    });
  });
}
