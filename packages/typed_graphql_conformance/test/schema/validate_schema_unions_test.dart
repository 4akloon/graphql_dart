import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: unions and
// enums. Locations are compared as graphql-js reports them; mapping/schema.csv
// says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: Union types must be valid', () {
    test('accepts a Union type with member types', () {
      final schema = port.build('''
      type Query {
        test: GoodUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union GoodUnion =
        | TypeA
        | TypeB
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects a Union type with empty types', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      union BadUnion
    ''');
      schema = port.extend(schema, '''
        directive @test on UNION

        extend union BadUnion @test
      ''');
      expect(port.errors(schema), [
        'Union type BadUnion must define one or more member types. @ 6:7',
      ]);
    });

    test('rejects a Union type with duplicated member type', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union BadUnion =
        | TypeA
        | TypeB
        | TypeA
    ''');
      expect(port.errors(schema), [
        'Union type BadUnion can only include type TypeA once. @ 15:11 '
            '17:11',
      ]);
      schema = schemas.extend(schema, 'extend union BadUnion = TypeB');
      expect(port.errors(schema), [
        'Union type BadUnion can only include type TypeA once. @ 15:11 '
            '17:11',
        'Union type BadUnion can only include type TypeB once. @ 16:11 '
            '1:25',
      ]);
    });

    test('rejects a Union type with non-Object members types', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union BadUnion =
        | TypeA
        | String
        | TypeB
    ''');
      schema = schemas.extend(schema, 'extend union BadUnion = Int');
      expect(port.errors(schema), [
        'Union type BadUnion can only include Object types, it cannot '
            'include String. @ 16:11',
        'Union type BadUnion can only include Object types, it cannot '
            'include Int. @ 1:25',
      ]);
      final badMembers = [
        'String',
        'SomeInterface',
        'SomeUnion',
        'SomeEnum',
        'SomeInputObject',
      ];
      for (final member in badMembers) {
        final badSchema = port.withFieldType(
          UnionType('BadUnion', memberTypes: [NamedTypeReference(member)]),
          types: port.someTypes,
        );
        expect(port.errors(badSchema), [
          'Union type BadUnion can only include Object types, it cannot include '
              '$member.',
        ]);
      }
    });
  });

  group('Type System: Enum types must be well defined', () {
    test('rejects an Enum type without values', () {
      var schema = port.build('''
      type Query {
        field: SomeEnum
      }

      enum SomeEnum
    ''');
      schema = port.extend(schema, '''
        directive @test on ENUM

        extend enum SomeEnum @test
      ''');
      expect(port.errors(schema), [
        'Enum type SomeEnum must define one or more values. @ 6:7',
      ]);
    });

    test('rejects an Enum type with incorrectly named values', () {
      final schema = port.withFieldType(
        EnumType('SomeEnum', values: [SchemaEnumValue('__badName')]),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });
}
