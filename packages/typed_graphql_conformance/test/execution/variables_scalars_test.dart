import 'package:test/test.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  group('Execute: Handles inputs', () {
    group('Handles custom enum values', () {
      test('allows custom enum values as inputs', () async {
        final result = await run('''
        {
          null: fieldWithEnumInput(input: NULL)
          NaN: fieldWithEnumInput(input: NAN)
          false: fieldWithEnumInput(input: FALSE)
          customValue: fieldWithEnumInput(input: CUSTOM)
          defaultValue: fieldWithEnumInput(input: DEFAULT_VALUE)
        }
      ''');

        expect(result, {
          'data': {
            'null': 'null',
            'NaN': 'NaN',
            'false': 'false',
            'customValue': '"custom value"',
            'defaultValue': '"DEFAULT_VALUE"',
          },
        });
      });

      test(
        'allows non-nullable inputs to have null as enum custom value',
        () async {
          final result = await run('''
        {
          fieldWithNonNullableEnumInput(input: NULL)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableEnumInput': 'null'},
          });
        },
      );
    });

    group('Handles nullable scalars', () {
      test('allows nullable inputs to be omitted', () async {
        final result = await run('''
        {
          fieldWithNullableStringInput
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test('allows nullable inputs to be omitted in a variable', () async {
        final result = await run(r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test(
        'allows nullable inputs to be omitted in an unlisted variable',
        () async {
          final result = await run(r'''
        query {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNullableStringInput': null},
          });
        },
      );

      test(
        'allows nullable inputs to be set to null in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        },
      );

      test(
        'allows nullable inputs to be set to a value in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': 'a'},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"a"'},
          });
        },
      );

      test('allows nullable inputs to be set to a value directly', () async {
        final result = await run('''
        {
          fieldWithNullableStringInput(input: "a")
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': '"a"'},
        });
      });
    });

    group('Handles non-nullable scalars', () {
      test(
        'allows non-nullable variable to be omitted given a default',
        () async {
          final result = await run(r'''
        query ($value: String! = "default") {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"default"'},
          });
        },
      );

      test(
        'allows non-nullable inputs to be omitted given a default',
        () async {
          final result = await run(r'''
        query ($value: String = "default") {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"default"'},
          });
        },
      );

      test(
        'does not allow non-nullable inputs to be omitted in a variable',
        () async {
          final result = await run(r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$value" has invalid value: Expected a value of non-null type "String!" to be provided.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        },
      );

      test(
        'does not allow non-nullable inputs to be set to null in a variable',
        () async {
          final result = await run(
            r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': null},
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$value" has invalid value: Expected value of non-null type "String!" not to be null.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        },
      );

      test(
        'allows non-nullable inputs to be set to a value in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': 'a'},
          );

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"a"'},
          });
        },
      );

      test(
        'allows non-nullable inputs to be set to a value directly',
        () async {
          final result = await run('''
        {
          fieldWithNonNullableStringInput(input: "a")
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"a"'},
          });
        },
      );

      test('reports error for missing non-nullable inputs', () async {
        final result = await run('{ fieldWithNonNullableStringInput }');

        expect(result, {
          'data': {'fieldWithNonNullableStringInput': null},
          'errors': [
            {
              'message': 'Argument "TestType.fieldWithNonNullableStringInput(input:)" of required type "String!" was not provided.',
              'locations': [
                {'line': 1, 'column': 3},
              ],
              'path': ['fieldWithNonNullableStringInput'],
            },
          ],
        });
      });

      test('reports error for array passed into string input', () async {
        final result = await run(
          r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
          variables: {
            'value': [1, 2, 3],
          },
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$value" has invalid value: String cannot represent a non string value: [1, 2, 3]',
              'locations': [
                {'line': 2, 'column': 16},
              ],
            },
          ],
        });
      });

      test(
        'reports error for non-provided variables for non-nullable inputs',
        () async {
          // Note: this test would typically fail validation before
          // encountering this execution error, however for queries which
          // previously validated and are being run against a new schema which
          // have introduced a breaking change to make a formerly non-required
          // argument required, this asserts failure before allowing the
          // underlying code to receive a non-null value.
          final result = await run(r'''

        {
          fieldWithNonNullableStringInput(input: $foo)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': null},
            'errors': [
              {
                'message': r'Argument "TestType.fieldWithNonNullableStringInput(input:)" has invalid value: Expected variable "$foo" provided to type "String!" to provide a runtime value.',
                'locations': [
                  {'line': 3, 'column': 50},
                ],
                'path': ['fieldWithNonNullableStringInput'],
              },
            ],
          });
        },
      );
    });

    // Note: the below is non-specified custom graphql-js behavior.
    group('Handles custom scalars with embedded variables', () {
      test('allows custom scalars', () async {
        final result = await run('''
        {
          fieldWithJSONScalarInput(input: { a: "foo", b: ["bar"], c: "baz" })
        }
      ''');

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });

      test('allows custom scalars with non-embedded variables', () async {
        final result = await run(
          r'''
          query ($input: JSONScalar) {
            fieldWithJSONScalarInput(input: $input)
          }
        ''',
          variables: {
            'input': {
              'a': 'foo',
              'b': ['bar'],
              'c': 'baz',
            },
          },
        );

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });

      test('allows custom scalars with embedded operation variables', () async {
        final result = await run(
          r'''
          query ($input: String) {
            fieldWithJSONScalarInput(input: { a: $input, b: ["bar"], c: "baz" })
          }
        ''',
          variables: {'input': 'foo'},
        );

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });
    });
  });
}
