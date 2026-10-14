import 'package:test/test.dart';

import '../validated.dart';

/// Types with thousands of fields, arguments and interfaces: the
/// implementation rules must look each up by name (R0.5).
void main() {
  const limit = Duration(seconds: 2);
  const count = 40000;

  (Duration, List<String>) timed(String text) {
    final watch = Stopwatch()..start();
    final errors = Validated(text).errors;
    return (watch.elapsed, errors);
  }

  test('an object with 20000 fields implements an interface of 20000', () {
    final fields = [for (var i = 0; i < count; i++) 'f$i: Int'].join(' ');
    final (elapsed, errors) = timed('''
interface I { $fields }
type Query implements I { $fields }''');
    expect(elapsed, lessThan(limit));
    expect(errors, isEmpty);
  });

  test('a field with 20000 arguments implements the same field', () {
    final arguments = [for (var i = 0; i < count; i++) 'a$i: Int'].join(' ');
    final (elapsed, errors) = timed('''
interface I { f($arguments): Int }
type Query implements I { f($arguments): Int }''');
    expect(elapsed, lessThan(limit));
    expect(errors, isEmpty);
  });

  test('a type that implements 40000 interfaces that share an ancestor', () {
    const interfaces = 40000;
    final names = [for (var i = 0; i < interfaces; i++) 'I$i'];
    final (elapsed, errors) = timed('''
interface Base { a: Int }
${[for (final name in names) 'interface $name implements Base { a: Int }'].join('\n')}
type Query implements ${names.join(' & ')} & Base { a: Int }''');
    expect(elapsed, lessThan(limit));
    expect(errors, isEmpty);
  });

  test('a type that repeats one interface stops at the error limit', () {
    final repeats = List.filled(count, 'I').join(' & ');
    final (elapsed, errors) = timed('''
interface I { a: Int }
type Query implements $repeats { a: Int }''');
    expect(elapsed, lessThan(limit));
    expect(errors, hasLength(101));
  });
}
