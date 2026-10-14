import 'package:test/test.dart';

import '../validated.dart';

void main() {
  test('an unknown directive points at the directive', () {
    final validated = Validated('''
type Query {
  foo: String @unknown
}''');
    expect(validated.errors, ['2:15 GQL117 Unknown directive "@unknown".']);
  });

  test('an unknown directive on the schema is reported', () {
    final validated = Validated('''
schema @unknown { query: Query }
type Query { a: Int }''');
    expect(validated.errors, ['1:8 GQL117 Unknown directive "@unknown".']);
  });

  test('a directive at a location it does not list is reported', () {
    final validated = Validated('type Query @deprecated { a: Int }');
    expect(validated.errors, [
      '1:12 GQL118 Directive "@deprecated" may not be used on OBJECT.',
    ]);
  });

  test('each element kind has its location', () {
    final validated = Validated('''
directive @d on QUERY
directive @e(a: Int @d) @d on FIELD
type Query @d { a(b: Int @d): E @d }
scalar S @d
interface I @d { a: Int }
union U @d = Query
enum E @d { A @d }
input In @d { a: Int @d }''');
    expect(validated.errors.map((error) => error.split(' may').first), [
      '2:25 GQL118 Directive "@d"',
      '2:21 GQL118 Directive "@d"',
      '3:12 GQL118 Directive "@d"',
      '3:33 GQL118 Directive "@d"',
      '3:26 GQL118 Directive "@d"',
      '4:10 GQL118 Directive "@d"',
      '5:13 GQL118 Directive "@d"',
      '6:9 GQL118 Directive "@d"',
      '7:8 GQL118 Directive "@d"',
      '7:15 GQL118 Directive "@d"',
      '8:10 GQL118 Directive "@d"',
      '8:22 GQL118 Directive "@d"',
    ]);
  });

  test('a directive at a location it lists is valid', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { a: Int @d }''');
    expect(validated.errors, isEmpty);
  });

  test('a directive that is not repeatable used twice is reported at both '
      'uses', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { a: Int @d @d }''');
    expect(validated.errors, [
      '2:21 GQL119 The directive "@d" can only be used once at this '
          'location. | 2:24',
    ]);
  });

  test('a repeatable directive may be used twice', () {
    final validated = Validated('''
directive @d repeatable on FIELD_DEFINITION
type Query { a: Int @d @d }''');
    expect(validated.errors, isEmpty);
  });

  test('an argument given twice is reported at the second', () {
    final validated = Validated('''
directive @d(a: Int) on FIELD_DEFINITION
type Query { f: Int @d(a: 1, a: 2) }''');
    expect(validated.errors, [
      '2:30 GQL120 There can be only one argument named "a". | 2:24',
    ]);
  });

  test('an argument the definition does not have is reported', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { f: Int @d(b: 1) }''');
    expect(validated.errors, [
      '2:24 GQL121 Unknown argument "b" on directive "@d".',
    ]);
  });

  test('a required argument left out is reported with its type', () {
    final validated = Validated('''
directive @d(a: [Int]!) on FIELD_DEFINITION
type Query { f: Int @d }''');
    expect(validated.errors, [
      '2:21 GQL122 Argument "@d(a:)" of type "[Int]!" is required, but it was '
          'not provided.',
    ]);
  });

  test('a non-null argument with a default value may be left out', () {
    final validated = Validated('''
directive @d(a: Int! = 1) on FIELD_DEFINITION
type Query { f: Int @d }''');
    expect(validated.errors, isEmpty);
  });

  test('the built-in directives are known', () {
    final validated = Validated('''
type Query { f: Int @deprecated(reason: "old") }
scalar Url @specifiedBy(url: "https://example.com")''');
    expect(validated.errors, isEmpty);
  });
}
