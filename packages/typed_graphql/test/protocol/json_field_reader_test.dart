import 'package:test/test.dart';
import 'package:typed_graphql/src/protocol/json_field_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final fields = JsonFieldReader(
    JsonObject({
      's': const JsonString('x'),
      'n': JsonNumber(1),
      'null': const JsonNull(),
      'o': JsonObject(const {}),
      'list': JsonArray([JsonNumber(1), JsonNumber(2)]),
    }),
  );

  DecodeResult<int> whole(JsonValue item) => switch (item) {
    JsonNumber(asInt: final int value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected an int'),
  };

  test('string requires a string', () {
    expect(fields.string('s'), const DecodeSuccess('x'));
    expect(
      fields.string('n'),
      const DecodeFailure('expected a string', path: [PathKey('n')]),
    );
    expect(
      fields.string('missing'),
      const DecodeFailure('is required', path: [PathKey('missing')]),
    );
    expect(fields.string('null'), isA<DecodeFailure>());
  });

  test('optionalString reads absent and null as null', () {
    expect(fields.optionalString('s'), const DecodeSuccess('x'));
    expect(
      fields.optionalString('missing'),
      const DecodeSuccess<String?>(null),
    );
    expect(fields.optionalString('null'), const DecodeSuccess<String?>(null));
    expect(fields.optionalString('n'), isA<DecodeFailure>());
  });

  test('optionalObject reads absent and null as null', () {
    expect(
      fields.optionalObject('o'),
      DecodeSuccess<JsonObject?>(JsonObject(const {})),
    );
    expect(
      fields.optionalObject('null'),
      const DecodeSuccess<JsonObject?>(null),
    );
    expect(
      fields.optionalObject('list'),
      const DecodeFailure('expected an object', path: [PathKey('list')]),
    );
  });

  test('optionalList reads every item', () {
    final result =
        fields.optionalList('list', whole) as DecodeSuccess<List<int>?>;
    expect(result.value, [1, 2]);
    expect(
      fields.optionalList('missing', whole),
      const DecodeSuccess<List<int>?>(null),
    );
  });

  test('optionalList places a bad item inside its index and key', () {
    final reader = JsonFieldReader(
      JsonObject({
        'list': JsonArray([JsonNumber(1), const JsonString('two')]),
      }),
    );
    expect(
      reader.optionalList('list', whole),
      const DecodeFailure(
        'expected an int',
        path: [PathKey('list'), PathIndex(1)],
      ),
    );
    expect(
      fields.optionalList('o', whole),
      const DecodeFailure('expected an array', path: [PathKey('o')]),
    );
  });
}
