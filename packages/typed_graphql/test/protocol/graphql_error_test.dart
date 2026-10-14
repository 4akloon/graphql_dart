import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<GraphQLError> decode(String text) =>
      GraphQLError.decode(json(text));

  final full = GraphQLError(
    'Name for character with ID 1002 could not be fetched.',
    locations: const [SourceLocation(6, 7)],
    path: const [
      PathKey('hero'),
      PathKey('heroFriends'),
      PathIndex(1),
      PathKey('name'),
    ],
    extensions: JsonObject({'code': const JsonString('CAN_NOT_FETCH_BY_ID')}),
  );

  group('toJson', () {
    test('writes the spec example, message first', () {
      expect(
        full.toJson().toString(),
        '{"message":"Name for character with ID 1002 could not be fetched.",'
        '"locations":[{"line":6,"column":7}],'
        '"path":["hero","heroFriends",1,"name"],'
        '"extensions":{"code":"CAN_NOT_FETCH_BY_ID"}}',
      );
    });

    test('leaves out empty locations and unset path and extensions', () {
      expect(GraphQLError('Boom').toJson().toString(), '{"message":"Boom"}');
    });

    test('writes an empty path when the path is empty', () {
      expect(
        GraphQLError('Boom', path: const []).toJson().toString(),
        '{"message":"Boom","path":[]}',
      );
    });
  });

  group('decode', () {
    test('reads what toJson writes', () {
      expect(GraphQLError.decode(full.toJson()), DecodeSuccess(full));
    });

    test('reads a path that mixes names and indexes', () {
      final error = decode('{"message": "m", "path": ["a", 0, "b", 12]}');
      expect(
        (error as DecodeSuccess<GraphQLError>).value.path,
        const [PathKey('a'), PathIndex(0), PathKey('b'), PathIndex(12)],
      );
    });

    test('reads 1.0 as the index 1, since the web cannot tell them apart', () {
      expect(
        decode('{"message": "m", "path": [1.0]}'),
        DecodeSuccess(GraphQLError('m', path: const [PathIndex(1)])),
      );
    });

    test('rejects an index that is negative or not whole', () {
      for (final index in ['-1', '1.5', '1e300', 'true', 'null']) {
        expect(
          decode('{"message": "m", "path": ["a", $index]}'),
          const DecodeFailure(
            'expected a string or an index from 0',
            path: [PathKey('path'), PathIndex(1)],
          ),
          reason: index,
        );
      }
    });

    test('rejects a location with a line or column below 1', () {
      for (final location in [
        '{"line": 0, "column": 1}',
        '{"line": 1, "column": 0}',
        '{"line": 1.5, "column": 1}',
        '{"line": 1}',
        '[1, 1]',
      ]) {
        final result = decode('{"message": "m", "locations": [$location]}');
        expect(
          (result as DecodeFailure).path,
          const [PathKey('locations'), PathIndex(0)],
          reason: location,
        );
      }
    });

    test('treats null and absent fields alike', () {
      expect(
        decode(
          '{"message": "m", "locations": null, "path": null, "extensions": null}',
        ),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('reads empty locations as none', () {
      expect(
        decode('{"message": "m", "locations": []}'),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('ignores keys the spec does not define', () {
      expect(
        decode('{"message": "m", "code": 42}'),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('requires a string message', () {
      expect(
        decode('{"locations": []}'),
        const DecodeFailure('is required', path: [PathKey('message')]),
      );
      expect(
        decode('{"message": null}'),
        const DecodeFailure('expected a string', path: [PathKey('message')]),
      );
      expect(decode('"m"'), const DecodeFailure('expected an object'));
    });

    test('requires extensions to be an object', () {
      expect(
        decode('{"message": "m", "extensions": []}'),
        const DecodeFailure(
          'expected an object',
          path: [PathKey('extensions')],
        ),
      );
    });
  });

  group('equality', () {
    test('compares by JSON', () {
      expect(
        GraphQLError('m', path: const [PathIndex(0)]),
        GraphQLError('m', path: const [PathIndex(0)]),
      );
      expect(GraphQLError('m').hashCode, GraphQLError('m').hashCode);
      expect(GraphQLError('m'), isNot(GraphQLError('m', path: const [])));
    });

    test('copies its lists', () {
      final locations = [const SourceLocation(1, 1)];
      final error = GraphQLError('m', locations: locations);
      locations.clear();
      expect(error.locations, hasLength(1));
      expect(error.locations.clear, throwsUnsupportedError);
    });
  });
}
