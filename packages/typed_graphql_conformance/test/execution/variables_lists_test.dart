import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  Map<String, Object?> invalidVariable(String where, String message) => {
    'errors': [
      {
        'message': 'Variable "\$input" has invalid value$where: $message',
        'locations': [
          {'line': 2, 'column': 16},
        ],
      },
    ],
  };

  group('Execute: Handles inputs', () {
    group('Handles lists and nullability', () {
      const listDoc = r'''
        query ($input: [String]) {
          list(input: $input)
        }
      ''';
      const nnListDoc = r'''

        query ($input: [String]!) {
          nnList(input: $input)
        }
      ''';
      const listNNDoc = r'''

        query ($input: [String!]) {
          listNN(input: $input)
        }
      ''';
      const nnListNNDoc = r'''

        query ($input: [String!]!) {
          nnListNN(input: $input)
        }
      ''';

      test('allows lists to be null', () async {
        final result = await run(listDoc, variables: {'input': null});

        expect(result, {
          'data': {'list': 'null'},
        });
      });

      test('allows lists to contain values', () async {
        final result = await run(
          listDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'list': '["A"]'},
        });
      });

      test('allows lists to contain null', () async {
        final result = await run(
          listDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(result, {
          'data': {'list': '["A", null, "B"]'},
        });
      });

      test('does not allow non-null lists to be null', () async {
        final result = await run(nnListDoc, variables: {'input': null});

        expect(
          result,
          invalidVariable(
            '',
            'Expected value of non-null type "[String]!" not to be null.',
          ),
        );
      });

      test('allows non-null lists to contain values', () async {
        final result = await run(
          nnListDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'nnList': '["A"]'},
        });
      });

      test('allows non-null lists to contain null', () async {
        final result = await run(
          nnListDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(result, {
          'data': {'nnList': '["A", null, "B"]'},
        });
      });

      test('allows lists of non-nulls to be null', () async {
        final result = await run(listNNDoc, variables: {'input': null});

        expect(result, {
          'data': {'listNN': 'null'},
        });
      });

      test('allows lists of non-nulls to contain values', () async {
        final result = await run(
          listNNDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'listNN': '["A"]'},
        });
      });

      test('does not allow lists of non-nulls to contain null', () async {
        final result = await run(
          listNNDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(
          result,
          invalidVariable(
            ' at [1]',
            'Expected value of non-null type "String!" not to be null.',
          ),
        );
      });

      test('does not allow non-null lists of non-nulls to be null', () async {
        final result = await run(nnListNNDoc, variables: {'input': null});

        expect(
          result,
          invalidVariable(
            '',
            'Expected value of non-null type "[String!]!" not to be null.',
          ),
        );
      });

      test('allows non-null lists of non-nulls to contain values', () async {
        final result = await run(
          nnListNNDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'nnListNN': '["A"]'},
        });
      });

      test(
        'does not allow non-null lists of non-nulls to contain null',
        () async {
          final result = await run(
            nnListNNDoc,
            variables: {
              'input': ['A', null, 'B'],
            },
          );

          expect(
            result,
            invalidVariable(
              ' at [1]',
              'Expected value of non-null type "String!" not to be null.',
            ),
          );
        },
      );

      test('does not allow invalid types to be used as values', () async {
        final result = await run(
          r'''

        query ($input: TestType!) {
          fieldWithObjectInput(input: $input)
        }
      ''',
          variables: {
            'input': {
              'list': ['A', 'B'],
            },
          },
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$input" expected value of type "TestType!" which cannot be used as an input type.',
              'locations': [
                {'line': 2, 'column': 24},
              ],
            },
          ],
        });
      });

      test('does not allow unknown types to be used as values', () async {
        final result = await run(
          r'''

        query ($input: UnknownType!) {
          fieldWithObjectInput(input: $input)
        }
      ''',
          variables: {'input': 'WhoKnows'},
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$input" expected value of type "UnknownType!" which cannot be used as an input type.',
              'locations': [
                {'line': 2, 'column': 24},
              ],
            },
          ],
        });
      });
    });

    group('Execute: Uses argument default values', () {
      test('when no argument provided', () async {
        final result = await run('{ fieldWithDefaultArgumentValue }');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': '"Hello World"'},
        });
      });

      test('when omitted variable provided', () async {
        final result = await run(r'''
        query ($optional: String) {
          fieldWithDefaultArgumentValue(input: $optional)
        }
      ''');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': '"Hello World"'},
        });
      });

      test('not when argument cannot be coerced', () async {
        final result = await run('''

        {
          fieldWithDefaultArgumentValue(input: WRONG_TYPE)
        }
      ''');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': null},
          'errors': [
            {
              'message': 'Argument "TestType.fieldWithDefaultArgumentValue(input:)" has invalid value: String cannot represent a non string value: WRONG_TYPE',
              'locations': [
                {'line': 3, 'column': 48},
              ],
              'path': ['fieldWithDefaultArgumentValue'],
            },
          ],
        });
      });

      test(
        'when no runtime value is provided to a non-null argument',
        () async {
          final result = await run(r'''
        query optionalVariable($optional: String) {
          fieldWithNonNullableStringInputAndDefaultArgumentValue(input: $optional)
        }
      ''');

          expect(result, {
            'data': {
              'fieldWithNonNullableStringInputAndDefaultArgumentValue':
                  '"Hello World"',
            },
          });
        },
      );

      test('does not expose prototype argument names when omitted', () async {
        final result = await run('''
        {
          fieldWithPrototypeNamedArgument
        }
      ''');

        expect(result, {
          'data': {'fieldWithPrototypeNamedArgument': 'missing'},
        });
      });
    });

    group('getVariableValues: limit maximum number of coercion errors', () {
      const doc = r'''

      query ($input: [String!]) {
        listNN(input: $input)
      }
    ''';
      const input = {
        'input': [0, 1, 2],
      };

      Map<String, Object?> invalidValueError(int value, int index) => {
        'message':
            'Variable "\$input" has invalid value at [$index]: String cannot represent a non string value: $value',
        'locations': [
          {'line': 2, 'column': 14},
        ],
      };

      test('return all errors by default', () async {
        final result = await run(doc, variables: input);

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            invalidValueError(2, 2),
          ],
        });
      });

      test('when maxErrors is equal to number of errors', () async {
        final result = await run(
          doc,
          variables: input,
          options: const ExecutionOptions(
            maskErrors: false,
            maxCoercionErrors: 3,
          ),
        );

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            invalidValueError(2, 2),
          ],
        });
      });

      test('when maxErrors is less than number of errors', () async {
        final result = await run(
          doc,
          variables: input,
          options: const ExecutionOptions(
            maskErrors: false,
            maxCoercionErrors: 2,
          ),
        );

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            {
              'message': 'Too many errors processing variables, error limit reached. Execution aborted.',
            },
          ],
        });
      });
    });

    group('getVariableValues: own-property names', () {
      const doc = r'''
      query ($toString: String) {
        fieldWithNullableStringInput(input: $toString)
      }
    ''';

      test('does not expose prototype variable names when omitted', () async {
        final result = await run(doc, variables: {});

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test(
        'still returns provided variables with colliding names',
        () async {
          final result = await run(doc, variables: {'toString': 'value'});

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"value"'},
          });
        },
      );
    });

    group('getVariableValues: explicit undefined values', () {
      test('treats explicit undefined values as omitted', () async {
        final result = await run(r'''
      query ($input: String) {
        fieldWithNullableStringInput(input: $input)
      }
    ''', variables: {});

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });
    });
  });
}
