import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueArgumentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueArgumentNamesRule());

  group('Validate: Unique argument names', () {
    test('no arguments on field', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('no arguments on directive', () {
      expect(
        port.errors('''
      {
        field @directive
      }
    '''),
        isEmpty,
      );
    });

    test('argument on field', () {
      expect(
        port.errors('''
      {
        field(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('argument on directive', () {
      expect(
        port.errors('''
      {
        field @directive(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on two fields', () {
      expect(
        port.errors('''
      {
        one: field(arg: "value")
        two: field(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on field and directive', () {
      expect(
        port.errors('''
      {
        field(arg: "value") @directive(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on two directives', () {
      expect(
        port.errors('''
      {
        field @directive1(arg: "value") @directive2(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('multiple field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg2: "value", arg3: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('multiple directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg2: "value", arg3: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:15 3:30',
        ],
      );
    });

    test('many duplicate field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:15 3:30 3:45',
        ],
      );
    });

    test('duplicate directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:26 3:41',
        ],
      );
    });

    test('many duplicate directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:26 3:41 3:56',
        ],
      );
    });
  });
}
