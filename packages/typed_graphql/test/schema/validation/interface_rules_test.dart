import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  group('implemented interfaces', () {
    test('a type that implements a union points at the reference', () {
      expect(
        errorsOf('''
type Query { a: B }
union U = B
type B implements U { a: Int }'''),
        [
          '3:19 GQL131 Type B must only implement Interface types, it cannot '
              'implement U.',
        ],
      );
    });

    test('an interface that implements itself is circular', () {
      expect(
        errorsOf('''
type Query { a: I }
interface I implements I { a: Int }'''),
        [
          '2:24 GQL132 Type I cannot implement itself because it would create '
              'a circular reference.',
        ],
      );
    });

    test('an interface named twice points at both references', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I & I { a: Int }'''),
        ['3:19 GQL133 Type B can only implement I once. | 3:23'],
      );
    });

    test('a missing transitive interface points at both references', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
interface J implements I { a: Int }
type B implements J { a: Int }'''),
        [
          '3:24 GQL134 Type B must implement I because it is implemented by J. '
              '| 4:19',
        ],
      );
    });

    test('interfaces that implement each other are circular', () {
      expect(
        errorsOf('''
type Query { a: I }
interface I implements J { a: Int }
interface J implements I { a: Int }'''),
        [
          '3:24 GQL132 Type I cannot implement J because it would create a '
              'circular reference. | 2:24',
          '2:24 GQL132 Type J cannot implement I because it would create a '
              'circular reference. | 3:24',
        ],
      );
    });
  });

  group('implemented fields', () {
    test('a missing interface field points at the field and the type', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int b: Int }
type B implements I { a: Int }'''),
        [
          '2:22 GQL135 Interface field I.b expected but B does not provide '
              'it. | 3:1',
        ],
      );
    });

    test('a field of a type that is not a subtype points at both types', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int! }
type B implements I { a: Int }'''),
        [
          '2:18 GQL136 Interface field I.a expects type Int! but B.a is type '
              'Int. | 3:26',
        ],
      );
    });

    test('a covariant field type is accepted', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: I }
type B implements I { a: B! }'''),
        isEmpty,
      );
    });

    test('a missing interface argument points at it and the field', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a(x: Int): Int }
type B implements I { a: Int }'''),
        [
          '2:17 GQL137 Interface field argument I.a(x:) expected but B.a does '
              'not provide it. | 3:23',
        ],
      );
    });

    test('an argument of another type points at both types', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a(x: Int): Int }
type B implements I { a(x: Int!): Int }'''),
        [
          '2:20 GQL138 Interface field argument I.a(x:) expects type Int but '
              'B.a(x:) is type Int!. | 3:28',
        ],
      );
    });

    test('an added required argument points at it and the field', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a(y: Int!): Int }'''),
        [
          '3:25 GQL139 Argument "B.a(y:)" must not be required type "Int!" if '
              'not provided by the Interface field "I.a". | 2:15',
        ],
      );
    });

    test('an added optional argument is accepted', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a(y: Int, z: Int! = 1): Int }'''),
        isEmpty,
      );
    });

    test('a deprecated implementation of a live field is reported', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a: Int @deprecated }'''),
        [
          '3:30 GQL140 Interface field I.a is not deprecated, so '
              'implementation field B.a must not be deprecated. | 3:26',
        ],
      );
    });

    test('a field of an unknown type reports only the unknown type', () {
      expect(
        Validated('''
type Query { a: B }
interface I { a: Missing }
type B implements I { a: Int }''').codes,
        ['GQL116'],
      );
    });
  });
}
