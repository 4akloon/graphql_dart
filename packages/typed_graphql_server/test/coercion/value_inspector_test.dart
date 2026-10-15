import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/value_inspector.dart';

void main() {
  const inspector = ValueInspector();

  group('ValueInspector of Dart values', () {
    test('quotes strings as JSON', () {
      expect(inspector.inspect('a "b"'), r'"a \"b\""');
    });

    test('escapes control characters as JSON does', () {
      expect(inspector.inspect('a\nb\u0001\\'), r'"a\nb\u0001\\"');
    });

    test('prints null, booleans and numbers plainly', () {
      expect(
        [null, true, 3, 1.5, 2.0].map(inspector.inspect).toList(),
        ['null', 'true', '3', '1.5', '2'],
      );
    });

    test('prints an object as { key: value }', () {
      expect(inspector.inspect({'a': 1, 'b': 'x'}), '{ a: 1, b: "x" }');
    });

    test('prints empty containers compactly', () {
      expect(inspector.inspect(<Object?>[]), '[]');
      expect(inspector.inspect(<String, Object?>{}), '{}');
    });

    test('prints a list as [a, b]', () {
      expect(inspector.inspect([1, 'x', null]), '[1, "x", null]');
    });

    test('cuts a list after ten items, with the count left', () {
      expect(
        inspector.inspect(List<int>.generate(12, (i) => i)),
        '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, ... 2 more items]',
      );
    });

    test('says "1 more item" for exactly one left', () {
      expect(
        inspector.inspect(List<int>.generate(11, (i) => i)),
        '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, ... 1 more item]',
      );
    });

    test('prints nesting deeper than two levels as [Object] or [Array]', () {
      expect(
        inspector.inspect({
          'a': {
            'b': {'c': 1},
          },
        }),
        '{ a: { b: [Object] } }',
      );
      expect(
        inspector.inspect([
          [
            [1],
          ],
        ]),
        '[[[Array]]]',
      );
    });
  });

  group('ValueInspector of JSON values', () {
    test('reads a JsonValue like the plain value', () {
      final value = JsonObject({
        'a': JsonArray([
          JsonNumber(1),
          const JsonString('x'),
          const JsonNull(),
        ]),
        'b': const JsonBool(false),
      });
      expect(inspector.inspect(value), '{ a: [1, "x", null], b: false }');
    });

    test('cuts a JSON list after ten items', () {
      final value = JsonArray([for (var i = 0; i < 13; i++) JsonNumber(i)]);
      expect(inspector.inspect(value), endsWith(', ... 3 more items]'));
    });

    test('does not walk a value nested far deeper than it prints', () {
      JsonValue value = JsonNumber(1);
      for (var i = 0; i < 5000; i++) {
        value = JsonArray([value]);
      }
      expect(inspector.inspect(value), '[[[Array]]]');
    });
  });
}
