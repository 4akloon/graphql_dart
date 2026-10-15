import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  group('Execute: Handles inputs', () {
    group('Handles objects and nullability', () {
      group('using inline structs', () {
        test('executes with complex input', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: "foo", b: ["bar"], c: "baz"})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('properly parses single value to list', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: "foo", b: "bar", c: "baz"})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('properly parses null value to null', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: null, b: null, c: "C", d: null})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: null, b: null, c: "C", d: null }',
            },
          });
        });

        test('properly parses null value in list', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {b: ["A",null,"C"], c: "C"})
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': '{ b: ["A", null, "C"], c: "C" }'},
          });
        });

        test('does not use incorrect value', () async {
          final result = await run('''

          {
            fieldWithObjectInput(input: ["foo", "bar", "baz"])
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': null},
            'errors': [
              {
                'message': 'Argument "TestType.fieldWithObjectInput(input:)" has invalid value: Expected value of type "TestInputObject" to be an object, found: ["foo", "bar", "baz"].',
                'path': ['fieldWithObjectInput'],
                'locations': [
                  {'line': 3, 'column': 41},
                ],
              },
            ],
          });
        });

        test(
          'properly runs coerceInputLiteral on complex scalar types',
          () async {
            final result = await run('''
          {
            fieldWithObjectInput(input: {c: "foo", d: "ExternalValue"})
          }
        ''');

            expect(result, {
              'data': {
                'fieldWithObjectInput': '{ c: "foo", d: "InternalValue" }',
              },
            });
          },
        );

        test('errors on faulty scalar type input', () async {
          final result = await run('''

          {
            fieldWithObjectInput(input: {c: "foo", e: "bar"})
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': null},
            'errors': [
              {
                'message': 'Argument "TestType.fieldWithObjectInput(input:)" has invalid value at .e: FaultyScalarErrorMessage',
                'path': ['fieldWithObjectInput'],
                'locations': [
                  {'line': 3, 'column': 41},
                ],
              },
            ],
          });
        });
      });

      group('using variables', () {
        const doc = r'''

        query ($input: TestInputObject) {
          fieldWithObjectInput(input: $input)
        }
      ''';

        test('executes with complex input', () async {
          final result = await run(
            doc,
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
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('uses undefined when variable not provided', () async {
          final result = await run(r'''
          query q($input: String) {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

          expect(result, {
            'data': {'fieldWithNullableStringInput': null},
          });
        });

        test('uses null when variable provided explicit null value', () async {
          final result = await run(
            r'''
          query q($input: String) {
            fieldWithNullableStringInput(input: $input)
          }''',
            variables: {'input': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test(
          'preserves explicit null variables within input object literals',
          () async {
            final result = await run(
              r'''
          query q($input: String) {
            fieldWithObjectInput(input: { a: $input, c: "baz" })
          }''',
              variables: {'input': null},
            );

            expect(result, {
              'data': {'fieldWithObjectInput': '{ a: null, c: "baz" }'},
            });
          },
        );

        test(
          'treats explicitly undefined variable values as omitted',
          () async {
            final result = await run(r'''
          query q($input: String = "Default value") {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

            expect(result, {
              'data': {'fieldWithNullableStringInput': '"Default value"'},
            });
          },
        );

        test('uses default value when not provided', () async {
          final result = await run(r'''
          query ($input: TestInputObject = {a: "foo", b: ["bar"], c: "baz"}) {
            fieldWithObjectInput(input: $input)
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test(
          'reports invalid default values with variable definition locations',
          () async {
            final result = await run(
              r'query ($input: String = 123) { fieldWithNullableStringInput(input: $input) }',
            );

            expect(result, {
              'errors': [
                {
                  'message': r'Variable "$input" has invalid default value: String cannot represent a non string value: 123',
                  'locations': [
                    {'line': 1, 'column': 8},
                  ],
                },
              ],
            });
          },
        );

        test('includes suggestions for invalid default values', () async {
          final result = await run(
            r'query ($input: TestInputObject = { c: "ok", aa: "x" }) { fieldWithObjectInput(input: $input) }',
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid default value: Expected value of type "TestInputObject" not to include unknown field "aa". Did you mean "a"? Found: { c: "ok", aa: "x" }.',
                'locations': [
                  {'line': 1, 'column': 8},
                ],
              },
            ],
          });
        });

        test(
          'hides suggestions for invalid default values when specified',
          () async {
            final result = await run(
              r'query ($input: TestInputObject = { c: "ok", aa: "x" }) { fieldWithObjectInput(input: $input) }',
              options: const ExecutionOptions(
                maskErrors: false,
                includesSuggestions: false,
              ),
            );

            expect(result, {
              'errors': [
                {
                  'message': r'Variable "$input" has invalid default value: Expected value of type "TestInputObject" not to include unknown field "aa", found: { c: "ok", aa: "x" }.',
                  'locations': [
                    {'line': 1, 'column': 8},
                  ],
                },
              ],
            });
          },
        );

        test('does not use default value when provided', () async {
          final result = await run(
            r'''
            query q($input: String = "Default value") {
              fieldWithNullableStringInput(input: $input)
            }
          ''',
            variables: {'input': 'Variable value'},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"Variable value"'},
          });
        });

        test('uses explicit null value instead of default value', () async {
          final result = await run(
            r'''
          query q($input: String = "Default value") {
            fieldWithNullableStringInput(input: $input)
          }''',
            variables: {'input': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test('uses null default value when not provided', () async {
          final result = await run(r'''
          query q($input: String = null) {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test('properly parses single value to list', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': 'baz'},
            },
          );

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('executes with complex scalar input', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'c': 'foo', 'd': 'ExternalValue'},
            },
          );

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ c: "foo", d: "InternalValue" }',
            },
          });
        });

        test('errors on faulty scalar type input', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'c': 'foo', 'e': 'ExternalValue'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .e: FaultyScalarErrorMessage',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on null for nested non-null', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': null},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .c: Expected value of non-null type "String!" not to be null.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on incorrect type', () async {
          final result = await run(
            doc,
            variables: {'input': 'foo bar'},
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" to be an object, found: "foo bar".',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on omission of nested non-null', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" to include required field "c", found: { a: "foo", b: "bar" }.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on deep nested errors and with many errors', () async {
          final result = await run(
            r'''

          query ($input: TestNestedInputObject) {
            fieldWithNestedObjectInput(input: $input)
          }
        ''',
            variables: {
              'input': {
                'na': {'a': 'foo'},
              },
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .na: Expected value of type "TestInputObject" to include required field "c", found: { a: "foo" }.',
                'locations': [
                  {'line': 2, 'column': 18},
                ],
              },
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestNestedInputObject" to include required field "nb", found: { na: { a: "foo" } }.',
                'locations': [
                  {'line': 2, 'column': 18},
                ],
              },
            ],
          });
        });

        test('errors on addition of unknown input field', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': 'baz', 'extra': 'dog'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" not to include unknown field "extra", found: { a: "foo", b: "bar", c: "baz", extra: "dog" }.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });
      });
    });
  });
}
