import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();

  JsonValue parsed(String text) => switch (reader.parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  String nested(int depth) => '${'[' * depth}${']' * depth}';

  group('parse', () {
    test('reads every kind of value', () {
      expect(
        parsed('{"a": [1, 2.5, "s", true, null], "b": {}}'),
        JsonObject({
          'a': JsonArray([
            JsonNumber(1),
            JsonNumber(2.5),
            const JsonString('s'),
            const JsonBool(true),
            const JsonNull(),
          ]),
          'b': JsonObject(const {}),
        }),
      );
    });

    test('reads 1.0 as the whole number 1', () {
      final number = parsed('1.0') as JsonNumber;
      expect(number, JsonNumber(1));
      expect(number.asInt, 1);
    });

    test('reads integers past 2^53 - 1 without a safe int', () {
      final number = parsed('9007199254740993') as JsonNumber;
      expect(number.asInt, isNull);
      expect(
        (parsed('9007199254740991') as JsonNumber).asInt,
        9007199254740991,
      );
    });

    test('rejects a number too large to be finite', () {
      expect(reader.parse('1e400'), isA<DecodeFailure>());
      expect(
        reader.parse('{"a": [-1e400]}'),
        const DecodeFailure(
          '-Infinity is not a finite number',
          path: [PathKey('a'), PathIndex(0)],
        ),
      );
    });

    test('keeps the last value of a repeated key', () {
      expect(parsed('{"a": 1, "a": 2}'), JsonObject({'a': JsonNumber(2)}));
    });

    test('rejects text that is not JSON', () {
      for (final text in ['', '{', '{"a": 1,}', "{'a': 1}", 'NaN', '01']) {
        final result = reader.parse(text);
        expect(result, isA<DecodeFailure>(), reason: text);
        expect((result as DecodeFailure).message, startsWith('not JSON'));
      }
    });
  });

  group('depth', () {
    test('accepts nesting up to maxDepth', () {
      expect(reader.parse(nested(512)), isA<DecodeSuccess<JsonValue>>());
      expect(
        const JsonReader(maxDepth: 0).parse('"s"'),
        const DecodeSuccess<JsonValue>(JsonString('s')),
      );
    });

    test('rejects nesting past maxDepth before decoding', () {
      expect(
        reader.parse(nested(513)),
        const DecodeFailure('arrays and objects are nested deeper than 512'),
      );
      expect(reader.parse(nested(100000)), isA<DecodeFailure>());
      expect(
        const JsonReader(maxDepth: 1).parse('{"a": {}}'),
        isA<DecodeFailure>(),
      );
    });

    test('does not count brackets inside strings', () {
      const reader = JsonReader(maxDepth: 1);
      expect(
        reader.parse(r'["[[{{", "\"[[", "\\"]'),
        isA<DecodeSuccess<JsonValue>>(),
      );
    });

    test('read rejects nesting past maxDepth too', () {
      const reader = JsonReader(maxDepth: 2);
      expect(reader.read([[]]), isA<DecodeSuccess<JsonValue>>());
      expect(
        reader.read([
          [<Object?>[]],
        ]),
        isA<DecodeFailure>(),
      );
    });
  });

  group('read', () {
    test('converts plain Dart objects', () {
      expect(
        reader.read({
          'a': [1, 'b', null],
        }),
        DecodeSuccess<JsonValue>(
          JsonObject({
            'a': JsonArray([
              JsonNumber(1),
              const JsonString('b'),
              const JsonNull(),
            ]),
          }),
        ),
      );
    });

    test('rejects a key that is not a string', () {
      expect(
        reader.read({
          'a': {1: 'x'},
        }),
        const DecodeFailure('the key 1 is not a string', path: [PathKey('a')]),
      );
    });

    test('rejects objects that are not JSON, with their path', () {
      expect(
        reader.read([1, DateTime(2026)]),
        const DecodeFailure('not a JSON value', path: [PathIndex(1)]),
      );
      expect(
        reader.read({'a': double.nan}),
        const DecodeFailure('NaN is not a finite number', path: [PathKey('a')]),
      );
    });

    test('rejects a list that contains itself', () {
      final list = <Object?>[];
      list.add(list);
      expect(reader.read(list), isA<DecodeFailure>());
    });
  });
}
