import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/lookahead/canonical_json.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();

  Future<String> fingerprint(
    String selectionText, {
    JsonObject? variables,
    String header = '',
  }) async => (await f.selection(
    'user',
    '$header{ user $selectionText }',
    variables: variables,
  )).fingerprint;

  group('fingerprint', () {
    test('writes names, arguments and children canonically', () async {
      expect(
        await fingerprint('{ name posts(first: 2, order: asc) { title } }'),
        'name,posts(first:2,order:"asc"){title}',
      );
    });

    test('ignores the order of fields', () async {
      expect(
        await fingerprint('{ posts { title } name }'),
        await fingerprint('{ name posts { title } }'),
      );
    });

    test('ignores the order of arguments', () async {
      expect(
        await fingerprint('{ posts(first: 1, order: asc) { title } }'),
        await fingerprint('{ posts(order: asc, first: 1) { title } }'),
      );
    });

    test('ignores aliases', () async {
      expect(
        await fingerprint('{ posts { title } }'),
        await fingerprint('{ list: posts { heading: title } }'),
      );
    });

    test('resolves variables to their values', () async {
      expect(
        await fingerprint(
          r'{ posts(first: $n) { title } }',
          header: r'query($n: Int) ',
          variables: JsonObject({'n': JsonNumber(4)}),
        ),
        await fingerprint('{ posts(first: 4) { title } }'),
      );
    });

    test('flattens fragments', () async {
      final selection = await f.selection('user', '''
        { user { ...Parts } }
        fragment Parts on User { name posts { title } }
      ''');
      expect(
        selection.fingerprint,
        await fingerprint('{ name posts { title } }'),
      );
    });

    test('differs when an argument value differs', () async {
      expect(
        await fingerprint('{ posts(first: 1) { title } }'),
        isNot(await fingerprint('{ posts(first: 2) { title } }')),
      );
    });

    test('differs when a field is added', () async {
      expect(
        await fingerprint('{ name }'),
        isNot(await fingerprint('{ name posts { title } }')),
      );
    });

    test('differs when a field sits at another level', () async {
      expect(
        await fingerprint('{ posts { title } name }'),
        isNot(await fingerprint('{ posts { title name } }')),
      );
    });

    test('differs when a skipped field comes back', () async {
      const header = r'query($s: Boolean!) ';
      const body = r'{ name posts @skip(if: $s) { title } }';
      expect(
        await fingerprint(
          body,
          header: header,
          variables: JsonObject({'s': const JsonBool(true)}),
        ),
        isNot(
          await fingerprint(
            body,
            header: header,
            variables: JsonObject({'s': const JsonBool(false)}),
          ),
        ),
      );
    });

    test('is empty for a selection with no fields', () async {
      expect(FieldSelection.empty.fingerprint, '');
    });

    test('of a one-thousand-level selection needs no recursion', () async {
      const depth = 1000;
      final text = '{ deep ${'{ deep ' * (depth - 1)}{ leaf }${' }' * depth}';
      final selection = await f.selection('deep', text);
      expect(
        selection.fingerprint,
        '${'deep{' * (depth - 1)}leaf${'}' * (depth - 1)}',
      );
    });

    test('lets has walk a one-thousand-level path', () async {
      const depth = 1000;
      final text = '{ deep ${'{ deep ' * (depth - 1)}{ leaf }${' }' * depth}';
      final selection = await f.selection('deep', text);
      expect(selection.has('${'deep.' * (depth - 1)}leaf'), isTrue);
    });
  });

  group('CanonicalJson', () {
    test('sorts the keys of objects at every level', () {
      final value = JsonObject({
        'b': JsonNumber(1),
        'a': JsonObject({'y': const JsonNull(), 'x': const JsonBool(true)}),
      });
      expect(
        const CanonicalJson().write(value),
        '{"a":{"x":true,"y":null},"b":1}',
      );
    });

    test('keeps the order of array items and quotes strings', () {
      final value = JsonArray([const JsonString('z"'), const JsonString('a')]);
      expect(const CanonicalJson().write(value), r'["z\"","a"]');
    });

    test('writes a value nested one thousand levels deep', () {
      JsonValue value = JsonNumber(0);
      for (var i = 0; i < 1000; i++) {
        value = JsonArray([value]);
      }
      expect(const CanonicalJson().write(value), '${'[' * 1000}0${']' * 1000}');
    });
  });
}
