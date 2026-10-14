import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('an object type without fields points at the type', () {
    expect(
      errorsOf('''
type Query { a: Empty }
type Empty'''),
      ['2:1 GQL125 Type Empty must define one or more fields.'],
    );
  });

  test('an interface type without fields is reported', () {
    expect(
      errorsOf('''
type Query { a: Empty }
interface Empty'''),
      ['2:1 GQL125 Type Empty must define one or more fields.'],
    );
  });

  test('a field of an input type points at its type', () {
    expect(
      errorsOf('''
type Query { a: [In!] }
input In { b: Int }'''),
      [
        '1:17 GQL126 The type of Query.a must be Output Type but got: [In!].',
      ],
    );
  });

  test('a field argument of an output type points at its type', () {
    expect(
      errorsOf('type Query { a(b: Query): Int }'),
      [
        '1:19 GQL127 The type of Query.a(b:) must be Input Type but got: '
            'Query.',
      ],
    );
  });

  test('a directive argument of an output type points at the argument', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(b: Query) on FIELD'''),
      [
        '2:14 GQL127 The type of @d(b:) must be Input Type but got: Query.',
      ],
    );
  });

  test('an input field of an output type points at its type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { c: Query }'''),
      ['2:15 GQL127 The type of In.c must be Input Type but got: Query.'],
    );
  });

  test('a deprecated required argument points at the directive and the '
      'type', () {
    expect(
      errorsOf('type Query { a(b: Int! @deprecated): Int }'),
      [
        '1:24 GQL128 Required argument Query.a(b:) cannot be deprecated. | '
            '1:19',
      ],
    );
  });

  test('a deprecated required input field is reported', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { c: Int! @deprecated }'''),
      [
        '2:20 GQL128 Required input field In.c cannot be deprecated. | 2:15',
      ],
    );
  });

  test('a deprecated argument with a default value is allowed', () {
    expect(
      errorsOf('type Query { a(b: Int! = 1 @deprecated): Int }'),
      isEmpty,
    );
  });
}
