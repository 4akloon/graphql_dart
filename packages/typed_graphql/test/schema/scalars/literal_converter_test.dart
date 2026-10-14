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
    expect(converter.convert(const IntValue('x')), isA<DecodeFailure>());
  });
}
