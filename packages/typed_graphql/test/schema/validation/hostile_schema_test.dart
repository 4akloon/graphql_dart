import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/validation/value_checker.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../validated.dart';

/// Schemas and values that try to make validation take quadratic time or
/// memory (R0.3, R0.5); each must finish in seconds with at most the
/// limit of errors.
void main() {
  const limit = Duration(seconds: 10);

  // Validates [text] and returns the time it took with the diagnostics.
  (Duration, List<String>) timed(String text) {
    final watch = Stopwatch()..start();
    final errors = Validated(text).errors;
    return (watch.elapsed, errors);
  }

  test('a required field missing 3500 times prints its object once', () {
    final fields = [for (var i = 0; i < 3500; i++) 'f$i: Int!'].join(' ');
    final big = 'x' * 1000000;
    final (elapsed, errors) = timed('''
type Query { q(a: T = {f0: 1, z: "$big"}): Int }
input T { $fields }''');
    expect(elapsed, lessThan(limit));
    // 100 errors and the limit.
    expect(errors, hasLength(101));
    expect(errors.last, contains('GQL000'));
    expect(errors.every((error) => error.length < 2000), isTrue);
    expect(errors.first, contains('found: { ... }'));
  });

  test('a small object keeps its whole text in the message', () {
    final (_, errors) = timed('''
type Query { q(a: T = {f0: 1}): Int }
input T { f0: Int! f1: Int! }''');
    expect(errors.single, contains('"f1", found: { f0: 1 }.'));
  });

  test('a union of repeated members stops at the error limit', () {
    final members = List.filled(40000, 'A').join(' | ');
    final (elapsed, errors) = timed('''
type A { a: Int }
type Query { a: A }
union U = $members''');
    expect(elapsed, lessThan(limit));
    expect(errors, hasLength(101));
  });

  test('a union of 120000 different members is valid in seconds', () {
    final names = [for (var i = 0; i < 120000; i++) 'T$i'];
    final (elapsed, errors) = timed('''
type Query { u: U }
${[for (final name in names) 'type $name { a: Int }'].join('\n')}
union U = ${names.join(' | ')}''');
    expect(elapsed, lessThan(limit));
    expect(errors, isEmpty);
  });

  test('input cycles beyond the limit do not build their text', () {
    const count = 4000;
    final inputs = [
      for (var i = 0; i < count; i++)
        'input T$i { a: T${(i + 1) % count}! b: T0! }',
    ].join('\n');
    final (elapsed, errors) = timed('type Query { q(a: T0): Int }\n$inputs');
    expect(elapsed, lessThan(limit));
    expect(errors, hasLength(101));
  });

  test('default values that form many cycles stop at the limit', () {
    const count = 4000;
    final inputs = [
      for (var i = 0; i < count; i++)
        'input T$i { a: T${(i + 1) % count} = {} b: T0 = {} }',
    ].join('\n');
    final (elapsed, errors) = timed('type Query { q(a: T0): Int }\n$inputs');
    expect(elapsed, lessThan(limit));
    expect(errors.length, lessThanOrEqualTo(101));
  });

  test('a chain of 16000 directives that apply each other is valid', () {
    const count = 16000;
    final directives = [
      for (var i = 0; i < count - 1; i++)
        'directive @d$i(a: Int @d${i + 1}) on ARGUMENT_DEFINITION',
      'directive @d${count - 1} on ARGUMENT_DEFINITION',
    ].join('\n');
    final (elapsed, errors) = timed('type Query { a: Int }\n$directives');
    expect(elapsed, lessThan(limit));
    expect(errors, isEmpty);
  });

  test('a ring of 16000 directives reports each, up to the limit', () {
    const count = 16000;
    final directives = [
      for (var i = 0; i < count; i++)
        'directive @d$i(a: Int @d${(i + 1) % count}) on ARGUMENT_DEFINITION',
    ].join('\n');
    final (elapsed, errors) = timed('type Query { a: Int }\n$directives');
    expect(elapsed, lessThan(limit));
    expect(errors, hasLength(101));
    expect(errors.first, contains('GQL130 Directive "@d0"'));
  });

  test('an Int literal of four million digits is out of range, fast', () {
    final schema = Built('type Query { a: Int }').schema;
    final watch = Stopwatch()..start();
    final problem = ValueChecker(
      schema,
    ).check(IntValue('9' * 4000000), const NamedType(Name('Int'))).single;
    expect(watch.elapsed, lessThan(limit));
    expect(problem.message, startsWith('Int cannot represent non 32-bit'));
  });

  test('Int literals that are no integer literal are rejected', () {
    final schema = Built('type Query { a: Int }').schema;
    String? messageOf(String text) => ValueChecker(
      schema,
    ).check(IntValue(text), const NamedType(Name('Int'))).firstOrNull?.message;
    expect(messageOf('0x10'), startsWith('Int cannot represent non-integer'));
    expect(messageOf('+5'), startsWith('Int cannot represent non-integer'));
    expect(messageOf('007'), startsWith('Int cannot represent non-integer'));
    expect(messageOf('-0'), isNull);
    expect(messageOf('2147483647'), isNull);
    expect(messageOf('-2147483648'), isNull);
    expect(messageOf('2147483648'), contains('non 32-bit'));
  });
}
