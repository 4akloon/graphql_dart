# Persisted Documents

A client may name a document by the SHA-256 of its text instead of sending
the text (R5.4). `GraphQLServer` reads the name from
`extensions.persistedQuery`, the shape Apollo clients send:

```text
{"version": 1, "sha256Hash": "<64 lower-case hexadecimal digits>"}
```

The hash is the lower-case hexadecimal SHA-256 of the text's UTF-8 bytes.
A server uses it in one of two ways, never both: automatic persisted
queries, where clients register their texts at run time, or trusted
documents, where the server runs only the texts it was given at build time.
Without either, a request that sends only a hash is refused with `GQL412`
and the message `PersistedQueryNotSupported`, which tells Apollo clients to
send texts again; a request with a text runs as usual.

## Automatic persisted queries

`GraphQLServer(persistedQueries:)` takes a `PersistedQueryStore`. A client
first sends only the hash. When the store does not hold it, the answer is
`GQL410` with the message `PersistedQueryNotFound`, and the client sends the
text with the hash; the server checks that the hash is the text's, runs it
and stores it. From then on the hash alone is enough.

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
    persistedQueries: MemoryPersistedQueryStore(),
  );
  const text = '{ hello }';
  final hash = sha256.convert(utf8.encode(text)).toString();
  final extensions = JsonObject({
    'persistedQuery': JsonObject({
      'version': JsonNumber(1),
      'sha256Hash': JsonString(hash),
    }),
  });
  Future<void> send(String? query) async {
    final response = await server.handle(
      ServerRequest(
        params: GraphQLRequest(query: query, extensions: extensions),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    if (response case SingleResponse(:final body)) print(body);
  }

  await send(null);
  await send(text);
  await send(null);
}
```

It prints:

```text
{"errors":[{"message":"PersistedQueryNotFound","extensions":{"code":"GQL410"}}]}
{"data":{"hello":"world"}}
{"data":{"hello":"world"}}
```

A hash always names its own text, so no client can make it serve another
document:

- A text whose SHA-256 is not the hash is refused with `GQL411` ("provided
  sha does not match query") and nothing is stored.
- A text is stored only after it parsed and validated; a refused document
  never enters the store.
- A text read from the store is checked against the document length limit
  and hashed again before it runs; a text that does not match its hash is
  treated as missing (`GQL410`), so a shared store that was written by
  someone else cannot change what a hash runs.
- A malformed extension (not an object, a version other than `1`, a hash
  that is not 64 lower-case hexadecimal digits) is `GQL413`. A JSON `null`
  is no extension.

`MemoryPersistedQueryStore` keeps the most recently used texts, 1000 by
default, and evicts the least recently used one past its capacity, so
clients that register many texts cannot grow it without bound.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final store = MemoryPersistedQueryStore(capacity: 1)
    ..write('a', '{ a }')
    ..write('b', '{ b }');
  print(store.read('a'));
  print(store.read('b'));
}
```

It prints:

```text
null
{ b }
```

A store shared by several servers (a database, a cache service)
implements `PersistedQueryStore`; both of its methods may return a
`Future`. An error a store throws is an unexpected error of the request:
it goes to `onError` and is masked as `GQL330` by the profile.

## Trusted documents

`TrustedDocuments` holds the only documents a server runs, by their hash.
A request names one by its hash alone, or sends its exact text; any other
text is refused with `GQL414` before it is parsed, a change of whitespace
included, and an unknown hash is `GQL415`. A text sent with a hash that is
not its own is `GQL411`. What runs is always the manifest's own text, never
the client's, and a trusted text longer than `maxDocumentLength` is refused
with `GQL401` like any other.

`TrustedDocuments.decode` reads the persisted-operations manifest that
`typed_graphql_codegen` writes for the client (`persisted_queries.json`,
Apollo's `apollo-persisted-query-manifest` format), whose ids are the
hashes of the minified texts the generated operations send.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

const manifest = '''
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    {
      "id": "9dd7ff987fac8d0d1979084ebde5ce8bd855cd066d1a34e98432275cc6bc264c",
      "name": "",
      "type": "query",
      "body": "{hello}"
    }
  ]
}
''';

Future<void> main() async {
  final decoded = switch (const JsonReader().parse(manifest)) {
    DecodeSuccess(:final value) => TrustedDocuments.decode(value),
    final DecodeFailure failure => failure,
  };
  // A broken manifest is a deployment error: the server must not start.
  final trusted = switch (decoded) {
    DecodeSuccess(:final value) => value,
    DecodeFailure() => throw StateError('Bad manifest: $decoded'),
  };
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
    trustedDocuments: trusted,
  );
  for (final text in ['{hello}', '{ hello }']) {
    final response = await server.handle(
      ServerRequest(
        params: GraphQLRequest(query: text),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    if (response case SingleResponse(:final body)) print(body);
  }
}
```

It prints:

```text
{"data":{"hello":"world"}}
{"errors":[{"message":"Only trusted documents are allowed.","extensions":{"code":"GQL414"}}]}
```

A manifest entry whose id is not the hash of its body is a `DecodeFailure`
with its path, such as `$.operations[0].id: expected the SHA-256 of the
body`, so an edited manifest cannot make a trusted hash run another text.
`TrustedDocuments(map)` builds the set from ids and texts in another format;
there a wrong id is an `ArgumentError`.

Trusted documents and automatic persisted queries together are an
`ArgumentError`: a store would let any client register a new document,
which is what trusted documents forbid.

## Diagnostic codes

| Code | When |
|---|---|
| `GQL410` | A hash the store does not hold, or whose stored text does not match it (`PersistedQueryNotFound`). |
| `GQL411` | A text sent with a hash that is not its SHA-256. |
| `GQL412` | A hash without a text, on a server with neither a store nor trusted documents (`PersistedQueryNotSupported`). |
| `GQL413` | A malformed `extensions.persistedQuery`. |
| `GQL414` | A text that is not a trusted document. |
| `GQL415` | A hash that names no trusted document. |

Each is a request error: the response has no `data`, the context is not
built and no resolver runs.
