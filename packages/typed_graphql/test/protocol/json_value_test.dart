import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('a switch over JsonValue is exhaustive', () {
    String kind(JsonValue value) => switch (value) {
      JsonNull() => 'null',
      JsonBool() => 'bool',
      JsonNumber() => 'number',
      JsonString() => 'string',
      JsonArray() => 'array',
      JsonObject() => 'object',
    };
    expect(kind(const JsonNull()), 'null');
    expect(kind(JsonObject(const {})), 'object');
  });

  group('JsonNumber', () {
    test('1 and 1.0 are equal, as on the web', () {
      expect(JsonNumber(1), JsonNumber(1.0));
      expect(JsonNumber(1).hashCode, JsonNumber(1.0).hashCode);
    });

    test('rejects NaN and the infinities', () {
      expect(() => JsonNumber(double.nan), throwsArgumentError);
      expect(() => JsonNumber(double.infinity), throwsArgumentError);
      expect(() => JsonNumber(double.negativeInfinity), throwsArgumentError);
    });

    test('asInt reads whole numbers up to 2^53 - 1', () {
      expect(JsonNumber(3).asInt, 3);
      expect(JsonNumber(3.0).asInt, 3);
      expect(JsonNumber(-3).asInt, -3);
      expect(JsonNumber(JsonNumber.maxSafeInteger).asInt, 9007199254740991);
      expect(JsonNumber(-JsonNumber.maxSafeInteger).asInt, -9007199254740991);
    });

    test('asInt is null for fractions and unsafe magnitudes', () {
      expect(JsonNumber(1.5).asInt, isNull);
      expect(JsonNumber(1e300).asInt, isNull);
      expect(JsonNumber(9007199254740992.0).asInt, isNull);
    });

    test('asInt holds the bounds of the safe range on both sides', () {
      expect(JsonNumber(-9007199254740991).asInt, -9007199254740991);
      expect(JsonNumber(-9007199254740992.0).asInt, isNull);
      expect(JsonNumber(-0.0).asInt, 0);
      expect(JsonNumber(1e20).asInt, isNull);
    });
  });

  group('equality', () {
    test('compares arrays item by item', () {
      expect(
        JsonArray([JsonNumber(1), const JsonString('a')]),
        JsonArray([JsonNumber(1.0), const JsonString('a')]),
      );
      expect(
        JsonArray([JsonNumber(1), JsonNumber(2)]),
        isNot(JsonArray([JsonNumber(2), JsonNumber(1)])),
      );
    });

    test('compares objects whatever the order of their keys', () {
      final ab = JsonObject({'a': JsonNumber(1), 'b': const JsonNull()});
      final ba = JsonObject({'b': const JsonNull(), 'a': JsonNumber(1)});
      expect(ab, ba);
      expect(ab.hashCode, ba.hashCode);
      expect(ab, isNot(JsonObject({'a': JsonNumber(1)})));
    });

    test('tells a JSON null from an absent key', () {
      final object = JsonObject({'a': const JsonNull()});
      expect(object['a'], const JsonNull());
      expect(object['b'], isNull);
      expect(object, isNot(JsonObject(const {})));
    });

    test('different kinds are never equal', () {
      expect(const JsonString('1'), isNot(JsonNumber(1)));
      expect(const JsonBool(false), isNot(const JsonNull()));
    });
  });

  group('immutability', () {
    test('copies the items and fields it is given', () {
      final items = <JsonValue>[JsonNumber(1)];
      final fields = <String, JsonValue>{'a': JsonNumber(1)};
      final array = JsonArray(items);
      final object = JsonObject(fields);
      items.clear();
      fields.clear();
      expect(array.items, hasLength(1));
      expect(object.fields, hasLength(1));
    });

    test('cannot be modified', () {
      expect(
        () => JsonArray(const []).items.add(const JsonNull()),
        throwsUnsupportedError,
      );
      expect(
        () => JsonObject(const {}).fields['a'] = const JsonNull(),
        throwsUnsupportedError,
      );
    });
  });

  group('toJson', () {
    test('gives plain Dart objects that jsonEncode writes', () {
      final value = JsonObject({
        'a': JsonArray([JsonNumber(1), const JsonBool(true), const JsonNull()]),
        'b': JsonObject({'c': const JsonString('d')}),
      });
      expect(value.toJson(), {
        'a': [1, true, null],
        'b': {'c': 'd'},
      });
      expect(jsonEncode(value.toJson()), '{"a":[1,true,null],"b":{"c":"d"}}');
    });

    test('toString is compact JSON', () {
      expect(
        JsonObject({
          'a': JsonArray([const JsonString('x')]),
        }).toString(),
        '{"a":["x"]}',
      );
    });
  });
}
