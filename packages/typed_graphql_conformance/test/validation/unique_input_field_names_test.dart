import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueInputFieldNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueInputFieldNamesRule());

  group('Validate: Unique input field names', () {
    test('input object with fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f: true })
      }
    '''),
        isEmpty,
      );
    });

    test('same input object within two args', () {
      expect(
        port.errors('''
      {
        field(arg1: { f: true }, arg2: { f: true })
      }
    '''),
        isEmpty,
      );
    });

    test('multiple input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f2: "value", f3: "value" })
      }
    '''),
        isEmpty,
      );
    });

    test('allows for nested input objects with similar fields', () {
      expect(
        port.errors('''
      {
        field(arg: {
          deep: {
            deep: {
              id: 1
            }
            id: 1
          }
          id: 1
        })
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f1: "value" })
      }
    '''),
        [
          'There can be only one input field named "f1". @ 3:22 3:35',
        ],
      );
    });

    test('many duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f1: "value", f1: "value" })
      }
    '''),
        [
          'There can be only one input field named "f1". @ 3:22 3:35',
          'There can be only one input field named "f1". @ 3:22 3:48',
        ],
      );
    });

    test('nested duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: {f2: "value", f2: "value" }})
      }
    '''),
        [
          'There can be only one input field named "f2". @ 3:27 3:40',
        ],
      );
    });
  });
}
