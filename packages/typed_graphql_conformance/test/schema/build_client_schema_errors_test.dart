import 'package:test/test.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the invalid introspection results. graphql-js throws at the first
// problem; `fromIntrospection` reports each as a diagnostic whose message
// starts with its JSON path instead of ending with the object. A kind
// used in the wrong place builds, and schema validation reports it.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    group('throws when given invalid introspection', () {
      const dummySchema = '''
      type Query {
        foo(bar: String): String
      }

      interface SomeInterface {
        foo: String
      }

      union SomeUnion = Query

      enum SomeEnum { FOO }

      input SomeInputObject {
        foo: String
      }

      directive @SomeDirective on QUERY
    ''';

      /// The result for the dummy schema, as plain objects to edit.
      Map<String, Object?> dummy() => port.introspectionOf(dummySchema);

      test('throws when introspection is missing __schema property', () {
        const message =
            r'GQL150 $: Invalid or incomplete introspection result. Ensure '
            'that you are passing "data" property of introspection response '
            'and no "errors" was returned alongside.';
        expect(port.errors(null), [message]);
        expect(port.errors(<String, Object?>{}), [message]);
      });

      test('throws when referenced unknown type', () {
        final introspection = dummy();
        (port.schemaIn(introspection)['types']! as List).removeWhere(
          (type) => (type! as Map<String, Object?>)['name'] == 'Query',
        );
        const unknown =
            'Invalid or incomplete schema, unknown type: Query. Ensure that a '
            'full introspection query is used in order to build a client '
            'schema.';
        expect(port.errors(introspection), [
          'GQL154 \$.__schema.types[1].possibleTypes[0]: $unknown',
          'GQL154 \$.__schema.queryType: $unknown',
        ]);
      });

      test(
        'throws when missing definition for one of the standard scalars',
        () {
          final introspection = port.introspectionOf(
            'type Query { foo: Float }',
          );
          (port.schemaIn(introspection)['types']! as List).removeWhere(
            (type) => (type! as Map<String, Object?>)['name'] == 'Float',
          );
          expect(port.errors(introspection), [
            r'GQL154 $.__schema.types[0].fields[0].type: Invalid or incomplete '
                'schema, unknown type: Float. Ensure that a full introspection '
                'query is used in order to build a client schema.',
          ]);
        },
      );

      test('throws when type reference is missing name', () {
        final introspection = dummy();
        (port.schemaIn(introspection)['queryType']! as Map).remove('name');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.queryType: Introspection result missing name.',
        ]);
      });

      test('throws when missing kind', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('kind');
        expect(port.errors(introspection), [
          r'GQL152 $.__schema.types[0]: Invalid or incomplete introspection '
              'result. Ensure that a full introspection query is used in order '
              'to build a client schema.',
        ]);
      });

      test('throws when missing interfaces', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('interfaces');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0]: Introspection result missing '
              'interfaces.',
        ]);
      });

      test('Legacy support for interfaces with null as interfaces field', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeInterface')['interfaces'] = null;
        expect(
          schemas.print(port.client(introspection)),
          schemas.print(schemas.build(dummySchema)),
        );
      });

      test('throws when missing fields', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('fields');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0]: Introspection result missing fields.',
        ]);
      });

      test('throws when missing field args', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        (fields.first! as Map).remove('args');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0].fields[0]: Introspection result '
              'missing field args.',
        ]);
      });

      test('throws when output type is used as an arg type', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        final argument =
            ((fields.first! as Map)['args']! as List).first! as Map;
        final type = argument['type']! as Map;
        expect(type['name'], 'String');
        type['name'] = 'SomeUnion';
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL127 The type of Query.foo(bar:) must be Input Type but got: '
              'SomeUnion.',
        ]);
      });

      test('throws when input type is used as a field type', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        final type = (fields.first! as Map)['type']! as Map;
        expect(type['name'], 'String');
        type['name'] = 'SomeInputObject';
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL126 The type of Query.foo must be Output Type but got: '
              'SomeInputObject.',
        ]);
      });

      test('throws when missing possibleTypes', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeUnion').remove('possibleTypes');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[2]: Introspection result missing '
              'possibleTypes.',
        ]);
      });

      test('throws when missing enumValues', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeEnum').remove('enumValues');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[3]: Introspection result missing '
              'enumValues.',
        ]);
      });

      test('throws when missing inputFields', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeInputObject').remove('inputFields');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[4]: Introspection result missing '
              'inputFields.',
        ]);
      });

      test('throws when missing directive locations', () {
        final introspection = dummy();
        final directives = port.schemaIn(introspection)['directives']! as List;
        final directive = directives.first! as Map;
        expect(directive['name'], 'SomeDirective');
        expect(directive['locations'], ['QUERY']);
        directive.remove('locations');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.directives[0]: Introspection result missing '
              'directive locations.',
        ]);
      });

      test('throws when missing directive args', () {
        final introspection = dummy();
        final directives = port.schemaIn(introspection)['directives']! as List;
        final directive = directives.first! as Map;
        expect(directive['name'], 'SomeDirective');
        expect(directive['args'], isEmpty);
        directive.remove('args');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.directives[0]: Introspection result missing '
              'directive args.',
        ]);
      });
    });

    group('very deep decorators are not supported', () {
      const tooDeep =
          r'GQL155 $.__schema.types[0].fields[0].type.ofType.ofType.ofType'
          '.ofType.ofType.ofType.ofType.ofType.ofType: Decorated type deeper '
          'than introspection query.';

      test('fails on very deep (> 8 levels) lists', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: [[[[[[[[[[String]]]]]]]]]]
        }
      ''');
        expect(port.errors(introspection), [tooDeep]);
      });

      test('fails on a very deep (> 8 levels) non-null', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: [[[[[String!]!]!]!]!]
        }
      ''');
        expect(port.errors(introspection), [tooDeep]);
      });

      test('succeeds on deep (<= 8 levels) types', () {
        final sdl = dedent('''
        type Query {
          foo: [[[[String!]!]!]!]!
        }
      ''');
        expect(port.cycle(sdl), sdl);
      });
    });

    // graphql-js throws while it builds; the model holds names, so the
    // client schema builds and the validator reports the kind.
    group('prevents infinite recursion on invalid introspection', () {
      test('recursive interfaces', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: Foo
        }

        type Foo implements Foo {
          foo: String
        }
      ''');
        expect(port.typeIn(introspection, 'Foo')['interfaces'], [
          {'kind': 'OBJECT', 'name': 'Foo', 'ofType': null},
        ]);
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL131 Type Foo must only implement Interface types, it cannot '
              'implement Foo.',
        ]);
      });

      test('recursive union', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: Foo
        }

        union Foo = Foo
      ''');
        expect(port.typeIn(introspection, 'Foo')['possibleTypes'], [
          {'kind': 'UNION', 'name': 'Foo', 'ofType': null},
        ]);
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL143 Union type Foo can only include Object types, it cannot '
              'include Foo.',
        ]);
      });
    });
  });
}
