import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const scalar = ScalarDataCodec(StringCodec());

  group('ScalarDataCodec', () {
    test('reads a value through its codec', () {
      expect(scalar.decode(const JsonString('a')), const DecodeSuccess('a'));
    });

    test('writes a value through its codec', () {
      expect(scalar.write('a'), const JsonString('a'));
    });

    test('reports a wrong value with the codec message and an empty path', () {
      final expected = const StringCodec().decode(JsonNumber(1));
      expect(expected, isA<DecodeFailure>());
      final result = scalar.decode(JsonNumber(1));
      expect(result, isA<DecodeFailure>());
      expect(
        (result as DecodeFailure).message,
        (expected as DecodeFailure).message,
      );
      expect(result.path, isEmpty);
    });
  });

  group('NullableDataCodec', () {
    const codec = NullableDataCodec(scalar);

    test('reads null', () {
      expect(
        codec.decode(const JsonNull()),
        const DecodeSuccess<String?>(null),
      );
    });

    test('reads a value', () {
      expect(
        codec.decode(const JsonString('a')),
        const DecodeSuccess<String?>('a'),
      );
    });

    test('writes null as JSON null', () {
      expect(codec.write(null), const JsonNull());
    });

    test('writes a value', () {
      expect(codec.write('a'), const JsonString('a'));
    });
  });

  group('ListDataCodec', () {
    const codec = ListDataCodec(scalar);

    test('reads the items', () {
      final result = codec.decode(
        JsonArray(const [JsonString('a'), JsonString('b')]),
      );
      expect((result as DecodeSuccess<List<String>>).value, ['a', 'b']);
    });

    test('reads an unmodifiable list', () {
      final result = codec.decode(JsonArray(const [JsonString('a')]));
      final list = (result as DecodeSuccess<List<String>>).value;
      expect(() => list.add('b'), throwsUnsupportedError);
    });

    test('reports a bad item at its index', () {
      final result = codec.decode(
        JsonArray([
          const JsonString('a'),
          const JsonString('b'),
          JsonNumber(1),
        ]),
      );
      expect((result as DecodeFailure).path, [const PathIndex(2)]);
    });

    test('reports a bad item of a nested list at both indexes', () {
      const nested = ListDataCodec(codec);
      final result = nested.decode(
        JsonArray([
          JsonArray(const [JsonString('a')]),
          JsonArray([JsonNumber(1)]),
        ]),
      );
      expect((result as DecodeFailure).path, [
        const PathIndex(1),
        const PathIndex(0),
      ]);
    });

    test('reports a value that is not a list with an empty path', () {
      final result = codec.decode(const JsonString('a'));
      expect((result as DecodeFailure).path, isEmpty);
    });

    test('writes the items', () {
      expect(
        codec.write(['a', 'b']),
        JsonArray(const [JsonString('a'), JsonString('b')]),
      );
    });
  });

  group('JsonDataCodec', () {
    test('keeps any JSON', () {
      final json = JsonObject({
        'a': JsonArray([JsonNumber(1)]),
      });
      expect(
        const JsonDataCodec().decode(json),
        DecodeSuccess<JsonValue>(json),
      );
    });

    test('writes the JSON as it is', () {
      expect(const JsonDataCodec().write(const JsonNull()), const JsonNull());
    });
  });
}
