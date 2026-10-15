import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const merger = JsonMerger();

  test('merges the fields of nested objects with one key', () {
    final JsonObject merged = merger.merge([
      JsonObject({
        'avatar': JsonObject({'url': const JsonString('u')}),
      }),
      JsonObject({
        'avatar': JsonObject({'size': JsonNumber(2)}),
      }),
    ]);
    expect(
      merged,
      JsonObject({
        'avatar': JsonObject({
          'url': const JsonString('u'),
          'size': JsonNumber(2),
        }),
      }),
    );
  });

  test('merges arrays by index', () {
    final JsonObject merged = merger.merge([
      JsonObject({
        'friends': JsonArray([
          JsonObject({'a': JsonNumber(1)}),
        ]),
      }),
      JsonObject({
        'friends': JsonArray([
          JsonObject({'b': JsonNumber(2)}),
          const JsonNull(),
        ]),
      }),
    ]);
    expect(
      merged,
      JsonObject({
        'friends': JsonArray([
          JsonObject({'a': JsonNumber(1), 'b': JsonNumber(2)}),
          const JsonNull(),
        ]),
      }),
    );
  });

  test('skips a null entry', () {
    expect(
      merger.merge([
        null,
        JsonObject({'a': JsonNumber(1)}),
      ]),
      JsonObject({'a': JsonNumber(1)}),
    );
  });

  test('keeps the fragment value when the later class writes null', () {
    expect(
      merger.merge([
        JsonObject({'a': JsonNumber(1)}),
        JsonObject({'a': const JsonNull()}),
      ]),
      JsonObject({'a': JsonNumber(1)}),
    );
  });

  test('lets the later value win for other pairs', () {
    expect(
      merger.merge([
        JsonObject({'a': JsonNumber(1)}),
        JsonObject({'a': const JsonString('x')}),
      ]),
      JsonObject({'a': const JsonString('x')}),
    );
  });
}
