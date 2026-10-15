import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/variable_literal_json.dart';

enum Mood { happy }

void main() {
  Value literal(String text) => switch (const Parser().parseValue(
    Source(text),
  )) {
    ParseElementSuccess<Value>(:final value) => value,
    _ => fail('did not parse: $text'),
  };

  DecodeResult<JsonValue> convert(
    String text, [
    Map<String, Object?> variables = const {},
  ]) => VariableLiteralJson(variables).convert(literal(text));

  JsonValue json(Object? plain) => switch (plain) {
    null => const JsonNull(),
    final bool flag => JsonBool(flag),
    final num number => JsonNumber(number),
    final String text => JsonString(text),
    final List<Object?> items => JsonArray([for (final i in items) json(i)]),
    final Map<String, Object?> fields => JsonObject({
      for (final e in fields.entries) e.key: json(e.value),
    }),
    _ => fail('not JSON'),
  };

  test('substitutes a variable inside an object', () {
    expect(
      convert(r'{ a: $v, b: ["bar"], c: "baz" }', {'v': 'foo'}),
      DecodeSuccess(
        json({
          'a': 'foo',
          'b': ['bar'],
          'c': 'baz',
        }),
      ),
    );
  });

  test('keeps an explicit null variable in an object', () {
    expect(
      convert(r'{ a: $v }', {'v': null}),
      DecodeSuccess(json({'a': null})),
    );
  });

  test('leaves a variable without a value out of an object', () {
    expect(convert(r'{ a: $v, b: 1 }'), DecodeSuccess(json({'b': 1})));
  });

  test('reads a variable without a value in a list as null', () {
    expect(convert(r'[1, $v]'), DecodeSuccess(json([1, null])));
  });

  test('substitutes a list and a map value', () {
    expect(
      convert(r'[$v]', {
        'v': [
          1,
          {'k': true},
        ],
      }),
      DecodeSuccess(
        json([
          [
            1,
            {'k': true},
          ],
        ]),
      ),
    );
  });

  test('refuses a coerced value that is not plain data', () {
    expect(
      convert(r'{ a: $v }', {'v': Mood.happy}),
      const DecodeFailure(
        r'The value of the variable "$v" cannot be written as JSON here.',
        path: [PathKey('a')],
      ),
    );
  });

  test('converts a literal without variables as LiteralConverter does', () {
    expect(
      convert('{ a: ENUM, b: 1.5 }'),
      DecodeSuccess(json({'a': 'ENUM', 'b': 1.5})),
    );
  });
}
