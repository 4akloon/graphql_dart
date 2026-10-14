import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('''
    type Query {
      search(criteria: Criteria!): [Business]
    }

    interface Node {
      id(format: String): ID
    }

    union Result = Business

    type Business implements Node {
      id(format: String): ID
      email: String @private(scope: "loggedIn")
    }

    input Criteria {
      filter: Filter
    }

    enum Filter {
      OPEN_NOW
    }

    directive @private(scope: String!) on FIELD_DEFINITION
  ''').schema;

  /// [text] parsed as a schema coordinate and resolved against the schema.
  CoordinateTarget? resolve(String text) =>
      switch (const Parser().parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => schema.resolve(value),
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  final business = schema.typeNamed('Business')! as ObjectType;
  final node = schema.typeNamed('Node')! as InterfaceType;
  final query = schema.typeNamed('Query')! as ObjectType;
  final criteria = schema.typeNamed('Criteria')! as InputObjectType;
  final filter = schema.typeNamed('Filter')! as EnumType;
  final private = schema.directiveNamed('private')!;

  group('Schema.resolve', () {
    test('resolves a declared and a built-in type', () {
      expect(resolve('Business'), TypeTarget(business));
      expect(resolve('String'), TypeTarget(schema.typeNamed('String')!));
    });

    test('resolves the field of an object and of an interface', () {
      expect(
        resolve('Business.email'),
        FieldTarget(business, business.fieldNamed('email')!),
      );
      expect(resolve('Node.id'), FieldTarget(node, node.fieldNamed('id')!));
    });

    test('gives null for a member of a union, which has no fields', () {
      expect(resolve('Result'), TypeTarget(schema.typeNamed('Result')!));
      expect(resolve('Result.Business'), isNull);
      expect(resolve('Result.x'), isNull);
    });

    test('resolves an input field and an enum value', () {
      expect(
        resolve('Criteria.filter'),
        InputFieldTarget(criteria, criteria.fieldNamed('filter')!),
      );
      expect(
        resolve('Filter.OPEN_NOW'),
        EnumValueTarget(filter, filter.valueNamed('OPEN_NOW')!),
      );
    });

    test('resolves a field argument', () {
      final search = query.fieldNamed('search')!;
      expect(
        resolve('Query.search(criteria:)'),
        ArgumentTarget(query, search, search.argumentNamed('criteria')!),
      );
    });

    test('resolves a declared and a built-in directive and arguments', () {
      expect(resolve('@private'), DirectiveTarget(private));
      expect(
        resolve('@private(scope:)'),
        DirectiveArgumentTarget(private, private.argumentNamed('scope')!),
      );
      final deprecated = schema.directiveNamed('deprecated')!;
      expect(
        resolve('@deprecated(reason:)'),
        DirectiveArgumentTarget(
          deprecated,
          deprecated.argumentNamed('reason')!,
        ),
      );
    });

    test('gives null for an element the schema lacks', () {
      for (final text in [
        'Unknown',
        'private',
        'Business.unknown',
        'Criteria.unknown',
        'Filter.UNKNOWN',
        'Business.id(unknown:)',
        '@unknown',
        '@Business',
        '@private(unknown:)',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    // The specification raises an error when a containing element is
    // missing or of the wrong kind; spec §9 keeps every miss a null.
    test('gives null when the containing element is missing or wrong', () {
      for (final text in [
        'Unknown.field',
        'String.field',
        'Unknown.field(arg:)',
        'Business.unknown(arg:)',
        'Criteria.filter(arg:)',
        'Filter.OPEN_NOW(arg:)',
        '@unknown(arg:)',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    // September2025 §2.14: meta-fields and introspection types are not
    // schema elements.
    test('gives null for meta-fields and introspection types', () {
      for (final text in [
        'Business.__typename',
        'Query.__type(name:)',
        '__Type',
        '__Directive.name',
        '__DirectiveLocation.INLINE_FRAGMENT',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    test('compares targets by the elements they hold', () {
      expect(TypeTarget(business), TypeTarget(business));
      expect(TypeTarget(business).hashCode, TypeTarget(business).hashCode);
      expect(TypeTarget(business), isNot(TypeTarget(query)));
      expect(DirectiveTarget(private), isNot(TypeTarget(business)));
    });
  });
}
