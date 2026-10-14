import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  group('finite values', () {
    test('nullable and list fields break a cycle', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In { a: In b: [In] c: [In!]! d: Other }
input Other { a: In }'''),
        isEmpty,
      );
    });

    test('a non-null self reference points at the field', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In { a: In! }'''),
        [
          '2:12 GQL148 Input Object In cannot be provided a finite value '
              'because it references itself through fields: In.a.',
        ],
      );
    });

    test('a cycle through two types points at every field', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { b: B! }
input B { a: A! }'''),
        [
          '2:11 GQL148 Input Object A cannot be provided a finite value '
              'because it references itself through fields: A.b, B.a. | 3:11',
        ],
      );
    });

    test('a type that reaches a cycle without being in it is not reported', () {
      expect(
        Validated('''
type Query { a(b: A): Int }
input A { b: B! }
input B { b: B! }''').errors,
        [
          '3:11 GQL148 Input Object B cannot be provided a finite value '
              'because it references itself through fields: B.b.',
        ],
      );
    });

    test('a OneOf type with one finite field is finite', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { a: In b: Int }'''),
        isEmpty,
      );
    });

    test('a OneOf type whose every field is infinite is reported', () {
      expect(
        Validated('''
type Query { a(b: In): Int }
input In @oneOf { a: In b: In }''').codes,
        ['GQL148', 'GQL148'],
      );
    });

    test('a long chain is checked without recursion', () {
      final types = [
        for (var i = 0; i < 20000; i++) 'input T$i { a: T${i + 1}! }',
      ];
      expect(
        Validated('''
type Query { a(b: T0): Int }
${types.join('\n')}
input T20000 { a: T0! }''').codes,
        ['GQL148'],
      );
    });
  });

  group('default value cycles', () {
    test('a default value that contains itself points at it', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { x: A = {} }'''),
        [
          '2:18 GQL149 Invalid circular reference. The default value of Input '
              'Object field A.x references itself.',
        ],
      );
    });

    test('a cycle through other defaults names them', () {
      expect(
        errorsOf('''
type Query { a(b: B): Int }
input B { x: B2 = {} }
input B2 { x: B = {} }'''),
        [
          '2:19 GQL149 Invalid circular reference. The default value of Input '
              'Object field B.x references itself via the default values of: '
              'B2.x. | 3:19',
        ],
      );
    });

    test('a cycle inside a list default is found', () {
      expect(
        Validated('''
type Query { a(b: C): Int }
input C { x: [C] = [{}] }''').codes,
        ['GQL149'],
      );
    });

    test('a default that gives the field a value breaks the cycle', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { x: A = { x: null } y: Int }'''),
        isEmpty,
      );
    });

    test('a long chain of defaults is walked without recursion', () {
      final types = [
        for (var i = 0; i < 20000; i++) 'input T$i { a: T${i + 1} = {} }',
      ];
      expect(
        Validated('''
type Query { a(b: T0): Int }
${types.join('\n')}
input T20000 { a: Int }''').codes,
        isEmpty,
      );
    });
  });
}
