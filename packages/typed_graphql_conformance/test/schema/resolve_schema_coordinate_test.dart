import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/resolveSchemaCoordinate-test.ts.
// graphql-js throws when an element that contains the coordinate is missing
// or of the wrong kind; `Schema.resolve` gives null (spec §9). Meta-fields
// and introspection types are not schema elements (September2025 §2.14),
// so they resolve to null where graphql-js resolves them.
void main() {
  const port = SchemaPort();
  final schema = port.build('''
  type Query {
    searchBusiness(criteria: SearchCriteria!): [Business]
  }

  input SearchCriteria {
    name: String
    filter: SearchFilter
  }

  enum SearchFilter {
    OPEN_NOW
    DELIVERS_TAKEOUT
    VEGETARIAN_MENU
  }

  type Business {
    id: ID
    name: String
    email: String @private(scope: "loggedIn")
  }

  directive @private(scope: String!) on FIELD_DEFINITION
''');

  /// graphql-js's `resolveSchemaCoordinate(schema, text)`.
  CoordinateTarget? resolveSchemaCoordinate(String text) =>
      switch (const Parser().parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => schema.resolve(value),
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  group('resolveSchemaCoordinate', () {
    test('resolves a Named Type', () {
      expect(
        resolveSchemaCoordinate('Business'),
        TypeTarget(schema.typeNamed('Business')!),
      );
      expect(
        resolveSchemaCoordinate('String'),
        TypeTarget(schema.typeNamed('String')!),
      );
      expect(resolveSchemaCoordinate('private'), isNull);
      expect(resolveSchemaCoordinate('Unknown'), isNull);
    });

    test('resolves a Type Field', () {
      final type = port.assertType<ObjectType>(schema, 'Business');
      expect(
        resolveSchemaCoordinate('Business.name'),
        FieldTarget(type, type.fieldNamed('name')!),
      );
      expect(resolveSchemaCoordinate('Business.unknown'), isNull);
      expect(resolveSchemaCoordinate('Unknown.field'), isNull);
      expect(resolveSchemaCoordinate('String.field'), isNull);
    });

    test('resolves a Input Field', () {
      final type = port.assertType<InputObjectType>(schema, 'SearchCriteria');
      expect(
        resolveSchemaCoordinate('SearchCriteria.filter'),
        InputFieldTarget(type, type.fieldNamed('filter')!),
      );
      expect(resolveSchemaCoordinate('SearchCriteria.unknown'), isNull);
    });

    test('resolves a Enum Value', () {
      final type = port.assertType<EnumType>(schema, 'SearchFilter');
      expect(
        resolveSchemaCoordinate('SearchFilter.OPEN_NOW'),
        EnumValueTarget(type, type.valueNamed('OPEN_NOW')!),
      );
      expect(resolveSchemaCoordinate('SearchFilter.UNKNOWN'), isNull);
    });

    test('resolves a Field Argument', () {
      final type = port.assertType<ObjectType>(schema, 'Query');
      final field = type.fieldNamed('searchBusiness')!;
      expect(
        resolveSchemaCoordinate('Query.searchBusiness(criteria:)'),
        ArgumentTarget(type, field, field.argumentNamed('criteria')!),
      );
      expect(resolveSchemaCoordinate('Business.name(unknown:)'), isNull);
      expect(resolveSchemaCoordinate('Unknown.field(arg:)'), isNull);
      expect(resolveSchemaCoordinate('Business.unknown(arg:)'), isNull);
      expect(resolveSchemaCoordinate('SearchCriteria.name(arg:)'), isNull);
    });

    test('resolves a Directive', () {
      expect(
        resolveSchemaCoordinate('@private'),
        DirectiveTarget(schema.directiveNamed('private')!),
      );
      expect(
        resolveSchemaCoordinate('@deprecated'),
        DirectiveTarget(schema.directiveNamed('deprecated')!),
      );
      expect(resolveSchemaCoordinate('@unknown'), isNull);
      expect(resolveSchemaCoordinate('@Business'), isNull);
    });

    test('resolves a Directive Argument', () {
      final directive = schema.directiveNamed('private')!;
      expect(
        resolveSchemaCoordinate('@private(scope:)'),
        DirectiveArgumentTarget(directive, directive.argumentNamed('scope')!),
      );
      expect(resolveSchemaCoordinate('@private(unknown:)'), isNull);
      expect(resolveSchemaCoordinate('@unknown(arg:)'), isNull);
    });
  });

  group('resolveSchemaCoordinate (meta-fields and introspection types)', () {
    test('resolves a meta-field', () {
      expect(resolveSchemaCoordinate('Business.__typename'), isNull);
    });

    test('resolves a meta-field argument', () {
      expect(resolveSchemaCoordinate('Query.__type(name:)'), isNull);
    });

    test('resolves an Introspection Type', () {
      expect(resolveSchemaCoordinate('__Type'), isNull);
    });

    test('resolves an Introspection Type Field', () {
      expect(resolveSchemaCoordinate('__Directive.name'), isNull);
    });

    test('resolves an Introspection Type Enum Value', () {
      expect(
        resolveSchemaCoordinate('__DirectiveLocation.INLINE_FRAGMENT'),
        isNull,
      );
    });
  });
}
