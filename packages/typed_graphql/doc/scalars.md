# Scalars and codecs

A schema says that a scalar called `DateTime` exists. It does not say how a
`DateTime` travels as JSON or what Dart type holds it; that is the job of a
codec. This package keeps the two apart: `ScalarType` is plain schema data and
has no behaviour, so one schema can serve a server, a client and a code
generator, each with the codecs it needs.

## The codec contract

`ScalarCodec<T>` has two methods:

- `decode(JsonValue)` reads input: a variable, a result value or a literal
  converted to JSON. It returns a `DecodeResult<T>`: a `DecodeSuccess` with the
  value, or a `DecodeFailure` that says why the value cannot be represented.
  It never throws.
- `encode(T)` writes a value as JSON. A value the type cannot hold can only come
  from code, so `encode` throws an `ArgumentError` for it.

The five built-in scalars have codecs, with graphql-js's error messages:

| Scalar | Codec | Dart type |
|---|---|---|
| `Int` | `IntCodec` | `int`, a signed 32-bit integer |
| `Float` | `FloatCodec` | `double` |
| `String` | `StringCodec` | `String` |
| `Boolean` | `BooleanCodec` | `bool` |
| `ID` | `IdCodec` | `String`; an integer input becomes its decimal text |

```dart
import 'package:typed_graphql/typed_graphql.dart';

String show<T>(DecodeResult<T> result) => switch (result) {
  DecodeSuccess(:final value) => 'ok: $value',
  DecodeFailure(:final message) => 'failed: $message',
};

void main() {
  const int32 = IntCodec();
  print(show(int32.decode(JsonNumber(42))));
  print(show(int32.decode(JsonNumber(3.0))));
  print(show(int32.decode(JsonNumber(1.5))));
  print(show(int32.decode(JsonNumber(4294967296))));
  print(show(int32.decode(const JsonString('42'))));

  // An ID accepts a string or an integer, and always gives a string.
  print(show(const IdCodec().decode(JsonNumber(7))));

  print(const BooleanCodec().encode(true));
  try {
    int32.encode(4294967296);
  } on ArgumentError catch (error) {
    print(error.message);
  }
}
```

It prints:

```text
ok: 42
ok: 3
failed: Int cannot represent non-integer value: 1.5
failed: Int cannot represent non 32-bit signed integer value: 4294967296
failed: Int cannot represent non-integer value: "42"
ok: 7
true
is not a 32-bit integer
```

## Registering codecs

`ScalarCodecs` maps scalar names to codecs. `const ScalarCodecs()` holds the
five built-ins. `withCodec(name, codec)` returns a new registry with one more
codec and leaves the first one alone, so a registry is safe to share. The
built-ins cannot be replaced: naming one is an `ArgumentError`, because the
specification fixes what they mean. `codecFor(name)` finds a codec or returns
null; the server and the client call it for every scalar they meet.

## A custom scalar

Write the codec for the Dart type you want, say a `DateTime` kept as an ISO 8601
string, and register it under the scalar's name.

```dart
import 'package:typed_graphql/typed_graphql.dart';

final class DateTimeCodec implements ScalarCodec<DateTime> {
  const DateTimeCodec();

  @override
  DecodeResult<DateTime> decode(JsonValue json) {
    if (json case JsonString(:final value)) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DecodeSuccess(parsed.toUtc());
      }
    }
    return DecodeFailure('DateTime cannot represent value: $json');
  }

  @override
  JsonValue encode(DateTime value) =>
      JsonString(value.toUtc().toIso8601String());
}

void main() {
  final codecs = const ScalarCodecs().withCodec(
    'DateTime',
    const DateTimeCodec(),
  );

  // The original registry is unchanged.
  print(const ScalarCodecs().codecFor('DateTime'));
  final codec = codecs.codecFor('DateTime')! as ScalarCodec<DateTime>;

  final moment = DateTime.utc(2026, 10, 14, 9, 30);
  print(codec.encode(moment));
  print(codec.decode(const JsonString('2026-10-14T09:30:00Z')));
  print(codec.decode(JsonNumber(1)));

  try {
    codecs.withCodec('Int', const DateTimeCodec());
  } on ArgumentError catch (error) {
    print(error.message);
  }
}
```

It prints:

```text
null
"2026-10-14T09:30:00.000Z"
DecodeSuccess(2026-10-14 09:30:00.000Z)
$: DateTime cannot represent value: 1
is a built-in scalar
```

The registry holds codecs as `ScalarCodec<Object>`, so a lookup returns the
codec without its type argument; cast it to the Dart type you registered, as
above. The typed server and the generated client do this for you.

## Literals

Input can also be a literal written in a document, such as a default value or an
argument. A literal is a language `Value` node, and a codec decodes `JsonValue`.
`LiteralConverter().convert(value)` bridges the two, so a codec has one entry
point and no `parseLiteral`: an enum value becomes its name as a string, a list
and an object convert element by element, and a variable has no value at this
point and fails.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const converter = LiteralConverter();
  final source = Source('{ f(a: 12, b: JEDI, c: [1, "two"], d: {x: true}) }');
  final document = const Parser().parse(source).requireDocument();
  final field = document.definitions.single as OperationDefinition;
  final selection = field.selectionSet.selections.single as Field;

  for (final argument in selection.arguments) {
    print('${argument.name.value}: ${converter.convert(argument.value)}');
  }

  // A literal that converts is then read by the scalar's codec.
  final converted = converter.convert(selection.arguments.first.value);
  if (converted case DecodeSuccess(:final value)) {
    print(const IntCodec().decode(value));
  }
}
```

It prints:

```text
a: DecodeSuccess(12)
b: DecodeSuccess("JEDI")
c: DecodeSuccess([1,"two"])
d: DecodeSuccess({"x":true})
DecodeSuccess(12)
```
