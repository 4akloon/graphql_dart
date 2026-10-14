import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('an invalid argument default points at the value, directives '
      'first', () {
    expect(
      errorsOf('''
type Query {
  field(arg: Int = 3.14): Int
}
directive @bad(arg: Int = 2.718) on FIELD'''),
      [
        '4:27 GQL123 @bad(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 2.718',
        '2:20 GQL123 Query.field(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 3.14',
      ],
    );
  });

  test('an invalid input field default names the field', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { field: Int = 3.14 }'''),
      [
        '2:25 GQL123 In.field has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ],
    );
  });

  test('a problem inside the value gives its path', () {
    expect(
      errorsOf('''
type Query { f(x: In = {a: [1, "2"]}): Int }
input In { a: [Int] }'''),
      [
        '1:32 GQL123 Query.f(x:) has invalid default value at .a[1]: Int '
            'cannot represent non-integer value: "2"',
      ],
    );
  });

  test('null for a non-null type is reported', () {
    expect(errorsOf('type Query { f(x: Int! = null): Int }'), [
      '1:26 GQL123 Query.f(x:) has invalid default value: Expected value of '
          'non-null type "Int!" not to be null.',
    ]);
  });

  test('a single value for a list type is a list of one', () {
    expect(errorsOf('type Query { f(x: [Int] = 1): Int }'), isEmpty);
  });

  test('a missing required field and an unknown field are reported', () {
    expect(
      errorsOf('''
type Query { f(x: In = {c: 1}): Int }
input In { a: Int! b: Int! = 1 }'''),
      [
        '1:24 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" to include required field "a", found: { c: 1 }.',
        '1:25 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" not to include unknown field "c", found: { c: 1 }.',
      ],
    );
  });

  test('a value that is not an object for an input object is reported', () {
    expect(
      errorsOf('''
type Query { f(x: In = 1): Int }
input In { a: Int }'''),
      [
        '1:24 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" to be an object, found: 1.',
      ],
    );
  });

  test('an enum value must be a known enum value', () {
    expect(
      errorsOf('''
type Query { f(x: E = B, y: E = "A"): Int }
enum E { A }'''),
      [
        '1:23 GQL123 Query.f(x:) has invalid default value: Value "B" does not '
            'exist in "E" enum.',
        '1:33 GQL123 Query.f(y:) has invalid default value: Enum "E" cannot '
            'represent non-enum value: "A".',
      ],
    );
  });

  test('each built-in scalar rejects a literal of another kind', () {
    final errors = errorsOf('''
type Query {
  f(a: String = 1, b: Boolean = 1, c: ID = 1.5, d: Float = "x", e: Int = 2147483648): Int
}''');
    expect(errors.map((error) => error.split('default value: ').last), [
      'String cannot represent a non string value: 1',
      'Boolean cannot represent a non boolean value: 1',
      'ID cannot represent a non-string and non-integer value: 1.5',
      'Float cannot represent non numeric value: "x"',
      'Int cannot represent non 32-bit signed integer value: 2147483648',
    ]);
  });

  test('the built-in scalars accept their literals', () {
    expect(
      errorsOf('''
type Query {
  f(a: String = "s", b: Boolean = true, c: ID = 1, d: Float = 1, e: Int = -2147483648): Int
}'''),
      isEmpty,
    );
  });

  test('a custom scalar accepts any literal', () {
    expect(
      errorsOf('''
type Query { f(a: Json = {a: [1, true, null]}): Int }
scalar Json'''),
      isEmpty,
    );
  });

  test('a OneOf input object needs exactly one non-null field', () {
    expect(
      errorsOf('''
type Query { f(a: In = {a: 1, b: 2}, b: In = {a: null}): Int }
input In @oneOf { a: Int b: Int }'''),
      [
        '1:24 GQL123 Query.f(a:) has invalid default value: Within OneOf Input '
            'Object type "In", exactly one field must be specified, and the '
            'value for that field must be non-null.',
        '1:46 GQL123 Query.f(b:) has invalid default value at .a: Within '
            'OneOf Input Object type "In", exactly one field must be specified, '
            'and the value for that field must be non-null.',
      ],
    );
  });

  test('an invalid directive argument value points at the value', () {
    expect(
      errorsOf('''
directive @d(a: [Int]) on FIELD_DEFINITION
type Query { f: Int @d(a: [1, "x"]) }'''),
      [
        '2:31 GQL124 Argument "@d(a:)" has invalid value at [1]: Int cannot '
            'represent non-integer value: "x"',
      ],
    );
  });
}
