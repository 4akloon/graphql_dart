import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueDirectivesPerLocationRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final extended = const SchemaPort().extend(
    RulePort.testSchema.schema,
    _extensionSdl,
  );
  final port = RulePort(
    const UniqueDirectivesPerLocationRule(),
    schema: switch (const SchemaValidator().validate(extended)) {
      final ValidSchema valid => valid,
      InvalidSchema(:final diagnostics) => fail('$diagnostics'),
    },
  );

  group('Validate: Directives Are Unique Per Location', () {
    test('no directives', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('unique directives in different locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA {
        field @directiveB
      }
    '''),
        isEmpty,
      );
    });

    test('unique directives in same locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA @directiveB {
        field @directiveA @directiveB
      }
    '''),
        isEmpty,
      );
    });

    test('same directives in different locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA {
        field @directiveA
      }
    '''),
        isEmpty,
      );
    });

    test('same directives in similar locations', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive
        field @directive
      }
    '''),
        isEmpty,
      );
    });

    test('repeatable directives in same location', () {
      expect(
        port.errors('''
      fragment Test on Type @repeatable @repeatable {
        field @repeatable @repeatable
      }
    '''),
        isEmpty,
      );
    });

    test('unknown directives must be ignored', () {
      expect(
        port.errors('''
      type Test @unknown @unknown {
        field: String! @unknown @unknown
      }

      extend type Test @unknown {
        anotherField: String!
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
        ],
      );
    });

    test('many duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
          'The directive "@directive" can only be used once at this location. @ 3:15 3:37',
        ],
      );
    });

    test('different duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directiveA @directiveB @directiveA @directiveB
      }
    '''),
        [
          'The directive "@directiveA" can only be used once at this location. @ 3:15 3:39',
          'The directive "@directiveB" can only be used once at this location. @ 3:27 3:51',
        ],
      );
    });

    test('duplicate directives in many locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directive @directive {
        field @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 2:29 2:40',
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
        ],
      );
    });
  });
}

const _extensionSdl = '''
  directive @directive on FIELD | FRAGMENT_DEFINITION
  directive @directiveA on FIELD | FRAGMENT_DEFINITION
  directive @directiveB on FIELD | FRAGMENT_DEFINITION
  directive @repeatable repeatable on FIELD | FRAGMENT_DEFINITION
''';
