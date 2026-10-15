import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'introspection_fixture.dart';

void main() {
  final fixture = IntrospectionFixture();

  Future<Map<String, Object?>> dataOf(String query) async {
    final json = await fixture.json(query);
    expect(json['errors'], isNull, reason: '$json');
    return json['data']! as Map<String, Object?>;
  }

  test(
    'answers IntrospectionQuery.full exactly as the core writes it',
    () async {
      final json = await fixture.json(IntrospectionQuery.full.text);
      final expected = fixture.built.schema.schema.toIntrospection(
        IntrospectionQuery.full,
      );
      expect(json['errors'], isNull);
      expect(json['data'], expected.toJson());
    },
  );

  test('answers the default query without the draft fields', () async {
    const query = IntrospectionQuery();
    final json = await fixture.json(query.text);
    expect(
      json['data'],
      fixture.built.schema.schema.toIntrospection(query).toJson(),
    );
  });

  test('__type finds a type by name', () async {
    final data = await dataOf('{ __type(name: "Account") { kind name } }');
    expect(data['__type'], {'kind': 'OBJECT', 'name': 'Account'});
  });

  test('__type of a missing type is null', () async {
    final data = await dataOf('{ __type(name: "Nope") { name } }');
    expect(data['__type'], isNull);
  });

  test('__type of a built-in scalar the schema does not use is null', () async {
    final data = await dataOf('{ __type(name: "Float") { name } }');
    expect(data['__type'], isNull);
  });

  test('__type still answers for an introspection type', () async {
    final data = await dataOf('{ __type(name: "__Schema") { name } }');
    expect(data['__type'], {'name': '__Schema'});
  });

  test('__type takes its name from a variable', () async {
    final json = await fixture.json(
      r'query ($n: String!) { __type(name: $n) { name } }',
      variables: JsonObject({'n': const JsonString('Robot')}),
    );
    expect(json['data'], {
      '__type': {'name': 'Robot'},
    });
  });

  test('list and non-null types nest through ofType', () async {
    final data = await dataOf('''
{
  __type(name: "Query") {
    fields {
      name
      type { kind name ofType { kind name ofType { kind name ofType { name } } } }
    }
  }
}''');
    final fields = (data['__type']! as Map<String, Object?>)['fields']!;
    final search = (fields as List<Object?>).cast<Map<String, Object?>>().first;
    expect(search['type'], {
      'kind': 'NON_NULL',
      'name': null,
      'ofType': {
        'kind': 'LIST',
        'name': null,
        'ofType': {
          'kind': 'NON_NULL',
          'name': null,
          'ofType': {'name': 'Search'},
        },
      },
    });
  });

  test('deprecated fields are left out unless asked for', () async {
    final data = await dataOf('''
{
  __type(name: "Query") {
    plain: fields { name }
    all: fields(includeDeprecated: true) { name isDeprecated deprecationReason }
  }
}''');
    final type = data['__type']! as Map<String, Object?>;
    expect(type['plain'], [
      {'name': 'search'},
      {'name': 'me'},
    ]);
    expect((type['all']! as List<Object?>).last, {
      'name': 'old',
      'isDeprecated': true,
      'deprecationReason': 'Use me.',
    });
  });

  test('deprecated enum values and arguments follow the same rule', () async {
    final data = await dataOf('''
{
  role: __type(name: "Role") {
    plain: enumValues { name }
    all: enumValues(includeDeprecated: true) { name }
  }
  robot: __type(name: "Robot") {
    fields(includeDeprecated: true) {
      plain: args { name }
      all: args(includeDeprecated: true) { name }
    }
  }
}''');
    final role = data['role']! as Map<String, Object?>;
    expect(role['plain'], [
      {'name': 'admin'},
    ]);
    expect(role['all'], [
      {'name': 'admin'},
      {'name': 'guest'},
    ]);
    final field =
        ((data['robot']! as Map<String, Object?>)['fields']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .last;
    expect(field['plain'], isEmpty);
    expect(field['all'], [
      {'name': 'unit'},
    ]);
  });

  test('a default value is printed as GraphQL', () async {
    final data = await dataOf('''
{ __type(name: "Query") { fields { args { name defaultValue } } } }''');
    final fields = (data['__type']! as Map<String, Object?>)['fields']!;
    final search = (fields as List<Object?>).first! as Map<String, Object?>;
    expect(search['args'], [
      {'name': 'term', 'defaultValue': '"all"'},
      {'name': 'by', 'defaultValue': null},
    ]);
  });

  test('__typename names the introspection types', () async {
    final data = await dataOf(
      '{ __schema { __typename types { __typename } } }',
    );
    final schema = data['__schema']! as Map<String, Object?>;
    expect(schema['__typename'], '__Schema');
    expect((schema['types']! as List<Object?>).first, {'__typename': '__Type'});
  });

  test('a mutation root has no __schema or __type', () async {
    final json = await fixture.json(
      'mutation { __typename __type(name: "Query") { name } }',
    );
    expect(json['data'], {'__typename': 'Mutation'});
  });

  group('IntrospectionPolicy.disabled', () {
    const disabled = ExecutionOptions(
      introspection: IntrospectionPolicy.disabled,
    );

    test('makes __type a GQL338 field error and keeps __typename', () async {
      final json = await fixture.json(
        '{ __type(name: "Query") { name } kind: __typename }',
        options: disabled,
      );
      expect(json['data'], {'__type': null, 'kind': 'Query'});
      final errors = (json['errors']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(errors.single['path'], ['__type']);
      expect(errors.single['message'], contains('"__type"'));
      expect(errors.single['extensions'], {'code': 'GQL338'});
    });

    test('makes __schema a GQL338 error that nulls the data', () async {
      final json = await fixture.json(
        '{ __schema { queryType { name } } }',
        options: disabled,
      );
      expect(json['data'], isNull);
      final errors = json['errors']! as List<Object?>;
      expect((errors.single! as Map<String, Object?>)['extensions'], {
        'code': 'GQL338',
      });
    });

    test('does not stop ordinary fields', () async {
      final json = await fixture.json('{ me { name } }', options: disabled);
      expect(json['data'], {
        'me': {'name': 'a'},
      });
    });
  });
}
