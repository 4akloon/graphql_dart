import 'package:test/test.dart';

import '../validated.dart';

/// Branches of the validation rules that no other test reaches.
void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;
  List<String> codesOf(String sdl) => Validated(sdl).codes;

  test('a null default of a nullable argument is valid', () {
    expect(errorsOf('type Query { f(x: Int = null): Int }'), isEmpty);
  });

  test('a null default of a non-null argument is reported', () {
    expect(errorsOf('type Query { f(x: Int! = null): Int }'), [
      '1:26 GQL123 Query.f(x:) has invalid default value: Expected value of '
          'non-null type "Int!" not to be null.',
    ]);
  });

  test('a OneOf default with one field is valid', () {
    expect(
      errorsOf('''
type Query { f(x: O = {a: 1}): Int }
input O @oneOf { a: Int b: String }'''),
      isEmpty,
    );
  });

  test('a directive that references itself through each kind of type', () {
    expect(
      codesOf('''
directive @d(a: O) on FIELD_DEFINITION
type Query { a: Int }
type O { f: Int @d }'''),
      contains('GQL130'),
    );
    expect(
      codesOf('''
directive @d(a: U) on FIELD_DEFINITION
type Query { a: Int }
union U = O
type O { f: Int @d }'''),
      contains('GQL130'),
    );
    expect(
      codesOf('''
directive @d(a: I) on FIELD_DEFINITION
type Query { a: Int }
interface I { f: Int @d }'''),
      contains('GQL130'),
    );
    expect(
      codesOf('''
directive @d(a: E) on FIELD_DEFINITION
type Query { a: Int }
enum E { X @d }'''),
      contains('GQL130'),
    );
    expect(
      codesOf('''
directive @d(a: S) on SCALAR
scalar S @d(a: S)
type Query { a: S }'''),
      contains('GQL130'),
    );
  });

  test('an interface that inherits an unknown interface is left alone', () {
    expect(
      errorsOf('''
interface A implements Missing { a: Int }
type Query implements A { a: Int }'''),
      ['1:24 GQL116 Unknown type "Missing".'],
    );
  });

  test('a field of an unknown type is reported once, on the type', () {
    expect(
      errorsOf('''
interface A { a: Int }
type Query implements A { a: Missing }'''),
      ['2:30 GQL116 Unknown type "Missing".'],
    );
  });
}
