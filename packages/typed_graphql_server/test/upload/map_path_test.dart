import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/upload/map_path.dart';

void main() {
  test('a path 200 deep is replaced without recursion', () {
    const depth = 200;
    final open = '{"a":' * depth;
    final text = '{"query":"q","variables":$open[null]${'}' * depth}}';
    final operations = switch (const JsonReader(maxDepth: 400).parse(text)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => throw StateError(message),
    };
    final path = MapPath('variables.${'a.' * depth}0');
    expect(path.isNullIn(operations), isTrue);
    final replaced = path.replace(operations, const JsonString('token'));
    expect(path.isNullIn(replaced), isFalse);
    var node = replaced;
    for (final segment in path.segments) {
      node = switch (node) {
        JsonObject(:final fields) => fields[segment]!,
        JsonArray(:final items) => items[int.parse(segment)],
        _ => throw StateError('not a container'),
      };
    }
    expect(node, const JsonString('token'));
  });

  test('replacing leaves the other values shared', () {
    final operations = switch (const JsonReader(maxDepth: 8).parse(
      '{"variables":{"a":null,"b":[1]}}',
    )) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => throw StateError(message),
    };
    final replaced = MapPath(
      'variables.a',
    ).replace(operations, const JsonString('t')) as JsonObject;
    final variables = replaced.fields['variables']! as JsonObject;
    final original =
        (operations as JsonObject).fields['variables']! as JsonObject;
    expect(variables.fields['a'], const JsonString('t'));
    expect(identical(variables.fields['b'], original.fields['b']), isTrue);
  });
}
