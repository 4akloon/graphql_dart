import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const converter = LiteralConverter();

  /// The JSON of the literal [text].
  DecodeResult<JsonValue> convert(String text) =>
      converter.convert(switch (const Parser().parseValue(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      });

  test('converts each kind of constant', () {
    expect(convert('12'), DecodeSuccess<JsonValue>(JsonNumber(12)));
    expect(convert('1.5e1'), DecodeSuccess<JsonValue>(JsonNumber(15)));
    expect(convert('"s"'), const DecodeSuccess<JsonValue>(JsonString('s')));
    expect(convert('true'), const DecodeSuccess<JsonValue>(JsonBool(true)));
    expect(convert('null'), const DecodeSuccess<JsonValue>(JsonNull()));
    expect(convert('RED'), const DecodeSuccess<JsonValue>(JsonString('RED')));
  });

  test('converts lists and objects, the last of two fields winning', () {
    expect(
      convert('{a: [1, "x"], b: {c: null}, a: 2}'),
      DecodeSuccess<JsonValue>(
        JsonObject({
          'a': JsonNumber(2),
          'b': JsonObject({'c': const JsonNull()}),
        }),
      ),
    );
  });

  test('reads an integer too large for an int as a number', () {
    expect(
      convert('123456789012345678901234567890'),
      DecodeSuccess<JsonValue>(JsonNumber(1.2345678901234568e29)),
    );
  });

  test('rejects a number too large to be finite, with its path', () {
    expect(
      convert('{a: [1, 1e400]}'),
      const DecodeFailure(
        'The number 1e400 is too large.',
        path: [PathKey('a'), PathIndex(1)],
      ),
    );
  });

  test('rejects a variable', () {
    expect(
      converter.convert(const Variable(Name('v'))),
      const DecodeFailure(r'The variable "$v" has no value here.'),
    );
  });

  test('rejects a number node whose text is not a number', () {
    expect(
      converter.convert(const IntValue('x')),
      const DecodeFailure('"x" is not a number.'),
    );
  });

  test('rejects text that only num.tryParse reads', () {
    for (final text in ['0x1F', 'NaN', 'Infinity', ' 1']) {
      expect(
        converter.convert(IntValue(text)),
        DecodeFailure('"$text" is not a number.'),
        reason: text,
      );
    }
  });

  test('rejects a variable inside a list, with its path', () {
    expect(
      converter.convert(
        ListValue([const IntValue('1'), const Variable(Name('v'))]),
      ),
      const DecodeFailure(
        r'The variable "$v" has no value here.',
        path: [PathIndex(1)],
      ),
    );
  });

  test('rejects a variable inside an object, with its path', () {
    expect(
      converter.convert(
        ObjectValue([const ObjectField(Name('a'), Variable(Name('v')))]),
      ),
      const DecodeFailure(
        r'The variable "$v" has no value here.',
        path: [PathKey('a')],
      ),
    );
  });

  test('converts negative numbers and negative zero', () {
    expect(convert('-3'), DecodeSuccess<JsonValue>(JsonNumber(-3)));
    expect(convert('-0'), DecodeSuccess<JsonValue>(JsonNumber(0)));
  });

  test('converts an empty list and an empty object', () {
    expect(convert('[]'), DecodeSuccess<JsonValue>(JsonArray(const [])));
    expect(convert('{}'), DecodeSuccess<JsonValue>(JsonObject(const {})));
  });

  test('converts an enum value inside a list', () {
    expect(
      convert('[RED]'),
      DecodeSuccess<JsonValue>(JsonArray(const [JsonString('RED')])),
    );
  });

  test('converts a block string to its value', () {
    expect(
      convert('"""\n  a\n  b\n"""'),
      const DecodeSuccess<JsonValue>(JsonString('a\nb')),
    );
  });

  /// A list value nested [levels] deep, built without recursion.
  Value nestedList(int levels) {
    Value value = const IntValue('1');
    for (var level = 0; level < levels; level++) {
      value = ListValue([value]);
    }
    return value;
  }

  test('rejects nesting deeper than the supported depth without overflow', () {
    expect(
      converter.convert(nestedList(5000)),
      isA<DecodeFailure>().having(
        (failure) => failure.message,
        'message',
        contains('nested deeper than'),
      ),
    );
  });

  test('converts nesting just under the supported depth', () {
    expect(
      converter.convert(nestedList(JsonReader.maxSupportedDepth)),
      isA<DecodeSuccess<JsonValue>>(),
    );
  });
}
