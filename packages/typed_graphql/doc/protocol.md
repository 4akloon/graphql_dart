# Wire Protocol

The protocol layer is the GraphQL wire format as typed values: a request, a
response and an error, and `JsonValue`, the type of any JSON. Reading
untrusted input never throws; it gives a `DecodeResult`.

## JsonValue

`JsonValue` is a sealed family: `JsonNull`, `JsonBool`, `JsonNumber`,
`JsonString`, `JsonArray` and `JsonObject`. It is the type of arbitrary JSON in
every public signature, so a `switch` over it is checked by the compiler and
there is no `dynamic`.

Values are immutable and compare by value: arrays item by item, objects by
keys and values whatever their order. Every number is one `JsonNumber`, because
the web cannot tell `1` from `1.0`; `asInt` reads a whole number no larger than
2^53 - 1 the same way on every platform and is null otherwise. `toJson()` gives
plain Dart objects that `jsonEncode` writes, and `toString()` is compact JSON.

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(JsonValue value) => switch (value) {
  JsonNull() => 'null',
  JsonBool(:final value) => 'a boolean: $value',
  JsonNumber(:final asInt?) => 'a whole number: $asInt',
  JsonNumber(:final value) => 'a number: $value',
  JsonString(:final value) => 'a string of ${value.length} units',
  JsonArray(:final items) => 'an array of ${items.length}',
  JsonObject(:final fields) => 'an object with ${fields.keys.join(', ')}',
};

void main() {
  final values = [
    const JsonNull(),
    const JsonBool(true),
    JsonNumber(3),
    JsonNumber(2.5),
    const JsonString('hero'),
    JsonArray([JsonNumber(1), JsonNumber(2)]),
    JsonObject({'id': JsonNumber(7), 'tags': JsonArray([])}),
  ];
  values.map(describe).forEach(print);

  print(JsonNumber(1) == JsonNumber(1.0));
  print(JsonObject({'a': JsonNumber(1), 'b': JsonNull()}));
}
```

It prints:

```text
null
a boolean: true
a whole number: 3
a number: 2.5
a string of 4 units
an array of 2
an object with id, tags
true
{"a":1,"b":null}
```

## Reading JSON

`JsonReader` turns untrusted input into a `JsonValue`: `parse(text)` reads JSON
text, `read(object)` reads the output of `jsonDecode` or any plain Dart
objects. Bad input is a `DecodeFailure`: text that is not JSON, a number too
large to be finite (`1e400`), a map key that is not a string, and arrays and
objects nested deeper than `maxDepth` (512 by default, at most 1000). A key
repeated in one object keeps its last value, as `jsonDecode` does.

The depth is measured on the text before `jsonDecode` runs, because on the web
`jsonDecode` recurses once per level and would overflow the stack first.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader(maxDepth: 3);

  print(reader.parse('{"a": [1, 2]}'));
  print(reader.parse('{"a": ') is DecodeFailure);
  print(reader.parse('[1e400]'));
  print(reader.parse('[[[[1]]]]'));
  print(reader.read({'a': Object()}));
}
```

It prints:

```text
DecodeSuccess({"a":[1,2]})
true
$[0]: Infinity is not a finite number
$: arrays and objects are nested deeper than 3
$.a: not a JSON value
```

## Decode results

`DecodeResult<T>` is `DecodeSuccess<T>(value)` or `DecodeFailure(message,
path:)`. The `path` is a list of `PathSegment`s, a `PathKey(name)` for an object
key or a `PathIndex(index)` for an array item, from the root of the input to the
bad value; `toString` writes it as JSONPath. `inside(segment)` puts a failure
inside its parent, which is how a decoder of nested values builds the path.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const failure = DecodeFailure(
    'expected a string',
    path: [PathKey('errors'), PathIndex(0), PathKey('message')],
  );
  print(failure);

  const inner = DecodeFailure('expected a number');
  print(inner.inside(const PathIndex(2)).inside(const PathKey('ids')));
}
```

It prints:

```text
$.errors[0].message: expected a string
$.ids[2]: expected a number
```

## Requests

`GraphQLRequest` is a request as it travels over a transport: the body of a
GraphQL over HTTP POST, the payload of a graphql-ws `subscribe` message. Every
field is optional: `query`, `operationName`, `variables` and `extensions` (an
automatic persisted query sends only a hash in `extensions`). `decode` ignores
unknown keys, as GraphQL over HTTP requires, and fails on a mistyped field.
`toJson()` writes the fields that are set. Two requests are equal when their
JSON is.

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();
  const body =
      '{"query": "query Hero(\$id: ID!) { hero(id: \$id) { name } }",'
      ' "variables": {"id": "1002"}, "clientTag": "web"}';

  if (reader.parse(body) case DecodeSuccess(:final value)) {
    switch (GraphQLRequest.decode(value)) {
      case DecodeSuccess(value: GraphQLRequest(:final query, :final variables)):
        print(query);
        print(variables);
      case final DecodeFailure failure:
        print(failure);
    }
  }

  const request = GraphQLRequest(
    query: '{ hero { name } }',
    operationName: 'Hero',
  );
  print(jsonEncode(request.toJson()));

  print(GraphQLRequest.decode(JsonObject({'variables': JsonArray([])})));
}
```

It prints:

```text
query Hero($id: ID!) { hero(id: $id) { name } }
{"id":"1002"}
{"query":"{ hero { name } }","operationName":"Hero"}
$.variables: expected an object
```

## Errors

`GraphQLError` is an error of a response, in the format of the specification:
a `message`, the `locations` in the document it is about, the response `path`
of the field it is about (response names and list indexes from the root of
`data`) and `extensions`. A server writes it with `toJson()`; a client reads it
with `decode`. Two errors are equal when their JSON is.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final error = GraphQLError(
    'Name for character with ID 1002 could not be fetched.',
    locations: [const SourceLocation(6, 7)],
    path: [
      const PathKey('hero'),
      const PathKey('friends'),
      const PathIndex(1),
      const PathKey('name'),
    ],
    extensions: JsonObject({'code': const JsonString('NOT_FOUND')}),
  );
  print(error.toJson());

  final decoded = GraphQLError.decode(error.toJson());
  print(decoded == DecodeSuccess(error));

  print(GraphQLError.decode(JsonObject({'message': JsonNumber(7)})));
}
```

It prints:

```text
{"message":"Name for character with ID 1002 could not be fetched.","locations":[{"line":6,"column":7}],"path":["hero","friends",1,"name"],"extensions":{"code":"NOT_FOUND"}}
true
$.message: expected a string
```

## Responses

`ResponsePayload` is the body of a response: an `ExecutionResult` when the
operation ran, a `RequestErrorResult` when it did not. `ResponsePayload.decode`
tells them apart by the `data` key.

- `ExecutionResult` has `data` (null when an error left none), `errors` and
  `extensions`. Data and errors together are a partial result.
- `RequestErrorResult` is a request that failed before it ran, such as a syntax
  or validation error: no `data`, at least one error (an empty list is an
  `ArgumentError`).

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const body = '''
{
  "errors": [
    {
      "message": "Name for character with ID 1002 could not be fetched.",
      "locations": [{"line": 6, "column": 7}],
      "path": ["hero", "friends", 1, "name"]
    }
  ],
  "data": {"hero": {"name": "R2-D2", "friends": [null, null]}}
}''';

  final payload = switch (const JsonReader().parse(body)) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  switch (payload) {
    case DecodeSuccess(value: ExecutionResult(:final data, :final errors)):
      print('data: $data');
      print('first error at ${errors.first.path}');
    case DecodeSuccess(value: RequestErrorResult(:final errors)):
      print('the request failed: ${errors.first.message}');
    case final DecodeFailure failure:
      print('not a GraphQL response: $failure');
  }

  final failed = ResponsePayload.decode(
    JsonObject({
      'errors': JsonArray([
        GraphQLError('Syntax Error: Unexpected ")".').toJson(),
      ]),
    }),
  );
  print(failed);
}
```

It prints:

```text
data: {"hero":{"name":"R2-D2","friends":[null,null]}}
first error at [hero, friends, 1, name]
DecodeSuccess(RequestErrorResult({"errors":[{"message":"Syntax Error: Unexpected \")\"."}]}))
```

## Optional values

GraphQL tells an argument, input field or variable that was not given from one
given as `null`. `Optional<T>` holds that difference: `Optional.present(value)`
(the value may be `null` when `T` is nullable) or `Optional.absent()`. A
`switch` over it needs two cases.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void describe(Optional<String?> value) {
  switch (value) {
    case Present(value: final text?):
      print('present: $text');
    case Present():
      print('present null');
    case Absent():
      print('absent');
  }
}

void main() {
  describe(const Optional.present('Ada'));
  describe(const Optional.present(null));
  describe(const Optional.absent());
}
```

It prints:

```text
present: Ada
present null
absent
```
