import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/request_decoding.dart';
import 'package:typed_graphql_server/src/upload/upload_map.dart';
import 'package:typed_graphql_server/src/upload/upload_map_parser.dart';
import 'package:typed_graphql_server/src/upload/upload_map_result.dart';

void main() {
  JsonValue json(String text) =>
      switch (const JsonReader(maxDepth: 64).parse(text)) {
        DecodeSuccess(:final value) => value,
        DecodeFailure(:final message) => throw StateError(message),
      };

  const parser = UploadMapParser(3);
  const single =
      '{"query":"q","variables":{"file":null,"files":[null,null],'
      '"nested":{"deep":[{"f":null}]},"kept":null,"number":1}}';

  UploadMap valid(String map, [String operations = single]) =>
      switch (parser.parse(json(map), json(operations))) {
        UploadMapValid(:final map) => map,
        UploadMapInvalid(:final refusal) => throw StateError(refusal.message),
      };

  DecodingRefusal refusal(String map, [String operations = single]) =>
      switch (parser.parse(json(map), json(operations))) {
        UploadMapInvalid(:final refusal) => refusal,
        UploadMapValid() => throw StateError('expected a refusal'),
      };

  void expectRefusal(
    String map,
    int status,
    DiagnosticCode code,
    String message, [
    String operations = single,
  ]) {
    final result = refusal(map, operations);
    expect(result.status, status);
    expect(result.code, code);
    expect(result.message, message);
  }

  const malformedMap = 'The map field must be a JSON object of lists of paths.';
  const badPath = 'A map path must name a null value inside variables.';

  group('UploadMapParser accepts', () {
    test('a path to a variable of a single request', () {
      expect(valid('{"0":["variables.file"]}').entries, hasLength(1));
    });

    test('a path through a list index', () {
      expect(valid('{"0":["variables.files.1"]}').entries, hasLength(1));
    });

    test('a path through objects and lists', () {
      expect(
        valid('{"0":["variables.nested.deep.0.f"]}').entries,
        hasLength(1),
      );
    });

    test('a path into a batch item', () {
      const batch = '[{"variables":{"a":null}},{"variables":{"b":null}}]';
      expect(valid('{"x":["1.variables.b"]}', batch).entries, hasLength(1));
    });

    test('an empty map', () {
      expect(valid('{}').entries, isEmpty);
    });

    test('several paths under one key', () {
      final entry = valid('{"0":["variables.files.0","variables.files.1"]}');
      expect(entry.entries.single.paths, hasLength(2));
    });

    test('the keys in the order of the map', () {
      final map = valid('{"b":["variables.file"],"a":["variables.kept"]}');
      expect([for (final entry in map.entries) entry.field], ['b', 'a']);
    });
  });

  group('UploadMapParser refuses', () {
    test('a map that is not an object', () {
      expectRefusal(
        '[]',
        400,
        DiagnosticCode.malformedMultipartRequest,
        malformedMap,
      );
    });

    test('a key whose value is not a list', () {
      expectRefusal(
        '{"0":"variables.file"}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        malformedMap,
      );
    });

    test('a key whose list is empty', () {
      expectRefusal(
        '{"0":[]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        malformedMap,
      );
    });

    test('a path that is not a string', () {
      expectRefusal(
        '{"0":[1]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        malformedMap,
      );
    });

    test('more keys than maxFiles', () {
      expectRefusal(
        '{"a":["variables.file"],"b":["variables.kept"],'
            '"c":["variables.files.0"],"d":["variables.files.1"]}',
        413,
        DiagnosticCode.tooManyUploads,
        'The map may name at most 3 files.',
      );
    });

    test('more paths than maxFiles in total', () {
      expectRefusal(
        '{"a":["variables.file","variables.kept"],'
            '"b":["variables.files.0","variables.files.1"]}',
        413,
        DiagnosticCode.tooManyUploads,
        'The map may name at most 3 paths.',
      );
    });

    test('a path outside variables', () {
      expectRefusal(
        '{"0":["query"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a path to variables itself', () {
      expectRefusal(
        '{"0":["variables"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a path to a variable that does not exist', () {
      expectRefusal(
        '{"0":["variables.missing"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a path to a value that is not null', () {
      expectRefusal(
        '{"0":["variables.number"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a list index past the end', () {
      expectRefusal(
        '{"0":["variables.files.2"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a list index with a sign', () {
      expectRefusal(
        '{"0":["variables.files.+1"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a list index with a leading zero', () {
      expectRefusal(
        '{"0":["variables.files.01"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a list index that is not a number', () {
      expectRefusal(
        '{"0":["variables.files.x"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
      );
    });

    test('a batch path without an item index', () {
      const batch = '[{"variables":{"a":null}}]';
      expectRefusal(
        '{"0":["variables.a"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
        batch,
      );
    });

    test('a batch path whose index is past the batch', () {
      const batch = '[{"variables":{"a":null}}]';
      expectRefusal(
        '{"0":["1.variables.a"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
        batch,
      );
    });

    test('an operations value that is neither an object nor an array', () {
      expectRefusal(
        '{"0":["variables.a"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
        '"text"',
      );
    });

    test('a path to a null that is not inside variables', () {
      expectRefusal(
        '{"0":["extensions.a"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        badPath,
        '{"extensions":{"a":null},"variables":{}}',
      );
    });

    test('two paths that name the same place', () {
      expectRefusal(
        '{"a":["variables.file"],"b":["variables.file"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        'Two map paths name the same place.',
      );
    });

    test('the same path twice under one key', () {
      expectRefusal(
        '{"a":["variables.file","variables.file"]}',
        400,
        DiagnosticCode.malformedMultipartRequest,
        'Two map paths name the same place.',
      );
    });
  });

  group('UploadMap.apply', () {
    test('replaces a variable with the token', () {
      final result = valid(
        '{"0":["variables.file"]}',
      ).apply(json(single), {'0': 'upload:a'});
      expect(
        result.toJson(),
        json(
          '{"query":"q","variables":{"file":"upload:a",'
          '"files":[null,null],"nested":{"deep":[{"f":null}]},'
          '"kept":null,"number":1}}',
        ).toJson(),
      );
    });

    test('replaces list items and nested values', () {
      final map = valid(
        '{"0":["variables.files.0"],"1":["variables.files.1"],'
        '"2":["variables.nested.deep.0.f"]}',
      );
      final result = map.apply(json(single), {
        '0': 'upload:a',
        '1': 'upload:b',
        '2': 'upload:c',
      });
      expect(
        result.toJson(),
        json(
          '{"query":"q","variables":{"file":null,'
          '"files":["upload:a","upload:b"],'
          '"nested":{"deep":[{"f":"upload:c"}]},"kept":null,"number":1}}',
        ).toJson(),
      );
    });

    test('puts one key\'s token at all its paths', () {
      final map = valid('{"0":["variables.files.0","variables.files.1"]}');
      final result = map.apply(json(single), {'0': 'upload:a'});
      expect(
        (((result as JsonObject)['variables']! as JsonObject)['files']!)
            .toJson(),
        ['upload:a', 'upload:a'],
      );
    });

    test('replaces inside the item of a batch only', () {
      const batch = '[{"variables":{"a":null}},{"variables":{"a":null}}]';
      final result = valid(
        '{"0":["1.variables.a"]}',
        batch,
      ).apply(json(batch), {'0': 'upload:a'});
      expect(
        result.toJson(),
        json(
          '[{"variables":{"a":null}},{"variables":{"a":"upload:a"}}]',
        ).toJson(),
      );
    });

    test('leaves the operations it was given unchanged', () {
      final operations = json(single);
      valid('{"0":["variables.file"]}').apply(operations, {'0': 'upload:a'});
      expect(operations, json(single));
    });

    test('a key without a token is a StateError', () {
      expect(
        () => valid('{"0":["variables.file"]}').apply(json(single), {}),
        throwsStateError,
      );
    });
  });
}
