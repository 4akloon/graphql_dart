# Generated Operations

The code that `typed_graphql_codegen` generates for an operation compiles
against the types of this package. This version holds only that contract; the
client that sends operations arrives in a later release.

## The operation

A generated operation is a `GraphQLQuery`, a `GraphQLMutation` or a
`GraphQLSubscription`, the three kinds of the sealed `GraphQLOperation`. It
holds its `OperationDocument` (name, type, minified text and the SHA-256 of
the text), its variables as JSON, and `decodeData`, which reads the `data`
member of a response. `toRequest` builds the `GraphQLRequest` to send.

## Codecs

A `DataCodec<T>` reads one kind of value of a response and writes it back.
Generated code composes them as constants:

- `ScalarDataCodec` reads a scalar through a `ScalarCodec`, such as
  `StringCodec`.
- `EnumDataCodec` reads an enum by its name; a name the schema did not have
  when the code was generated becomes an unknown value (`DataEnum`).
- `ObjectDataCodec` reads a generated class (`DataObject`).
- `NullableDataCodec` and `ListDataCodec` wrap another codec.
- `JsonDataCodec` keeps a custom scalar that is not mapped as a `JsonValue`.

`DataContext` carries the variables, which decide whether a fragment under
`@include` or `@skip` was selected. `DataEquality` compares the members of
generated classes that hold lists or optionals. `JsonMerger` merges the JSON
of a class and its fragments when they select the same response name.

## Failures

`DataCodec.read` throws a `DataFormatException` for a value of the wrong
shape; `DataCodec.decode` never throws. It returns a `DecodeFailure` with the
message and the path of the value in the JSON it was given.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const codec = ListDataCodec(ListDataCodec(ScalarDataCodec(StringCodec())));
  final parsed = const JsonReader().parse('[["a"], [1]]');
  if (parsed case DecodeSuccess(:final value)) {
    if (codec.decode(value) case DecodeFailure(:final message, :final path)) {
      print(message);
      print(path);
    }
  }
}
```

It prints:

```text
String cannot represent a non string value: 1
[1, 0]
```
