# Uploads

A GraphQL multipart request carries files next to the operation (R5.6). The
client sends one `multipart/form-data` body whose parts are, in this order,
`operations` (a request, or a batch, as JSON), `map` (JSON: the name of each
file part and the places in `variables` it fills) and the files. This guide
wires uploads into a schema and a `GraphQLHttpHandler`, and lists the limits,
the CSRF rule and the storage contract.

## The pieces

- `Upload` is what a resolver reads: `filename`, `mediaType`, `length` and
  `openRead()`.
- `UploadStorage` is where a file waits until the response is built:
  `store` takes the file's bytes and returns an `Upload`, `release` frees it.
  `MemoryUploadStorage` keeps files in memory.
- `UploadLimits` bounds a request: `maxFiles`, `maxFileBytes`,
  `maxRequestBytes` and `maxFieldBytes`.
- `Uploads` holds a storage and the limits, and gives the schema its scalar.

## Wiring

One `Uploads` value is shared by the schema and the handler. The schema
declares the scalar with its codec; the handler gets the same value in its
options (`HttpOptions` is not a `const` expression then, because `Uploads`
holds the tokens of the requests being served):

```text
final uploads = Uploads();
final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
final handler = GraphQLHttpHandler<Object?>(
  server,
  options: HttpOptions(uploads: uploads),
);
```

The scalar is input only: encoding an `Upload` is an `ArgumentError`. A
variable of type `Upload` reaches the resolver as the file the request
carried; any other value is a coercion error, "Upload value is not a file of
this request." The reader puts a token such as `upload:` and 32 random hex
digits in the place of each file, so a client cannot name a file of another
request.

The `Uploads` value of the scalar and the one in `HttpOptions.uploads` must be
the same instance: the tokens live in it, and a scalar built from another
`Uploads` rejects every file with that coercion error. A token is valid for
any request in flight (it has 128 random bits, so it cannot be guessed), so
never log one.

This program builds a multipart body in memory, sends it through the handler
and prints the answer of the resolver:

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final uploads = Uploads();
  final b = ExecutableSchemaBuilder<Object?>();
  final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
  final file = Arg('file', upload);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('ok', b.string).pure((_) => 'ok')],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [
      t.field('upload', b.string, args: [file]).resolve((
        parent,
        args,
        context,
        info,
      ) async {
        final received = args.get(file);
        final bytes = await received.openRead().expand((c) => c).toList();
        return '${received.filename}: ${utf8.decode(bytes)}';
      }),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, mutation: mutation),
    contextFactory: (request) => null,
    profile: ServerProfile.development,
  );
  final handler = GraphQLHttpHandler<Object?>(
    server,
    options: HttpOptions(uploads: uploads),
  );

  const boundary = 'exampleBoundary';
  final operations = jsonEncode({
    'query': r'mutation ($file: Upload!) { upload(file: $file) }',
    'variables': {'file': null},
  });
  final body = [
    '--$boundary',
    'content-disposition: form-data; name="operations"',
    '',
    operations,
    '--$boundary',
    'content-disposition: form-data; name="map"',
    '',
    '{"0":["variables.file"]}',
    '--$boundary',
    'content-disposition: form-data; name="0"; filename="notes.txt"',
    'content-type: text/plain',
    '',
    'hello',
    '--$boundary--',
    '',
  ].join('\r\n');

  final response = await handler.handle(
    HttpRequestData(
      method: 'POST',
      uri: Uri.parse('http://localhost/graphql'),
      headers: {
        'content-type': 'multipart/form-data; boundary=$boundary',
        'graphql-require-preflight': 'true',
      },
      body: Stream.value(utf8.encode(body)),
    ),
  );

  print(response.status);
  if (response.body case FixedBody(:final bytes)) {
    print(utf8.decode(bytes));
  }
}
```

It prints:

```text
200
{"data":{"upload":"notes.txt: hello"}}
```

A multipart request runs like a JSON one: queries and mutations, never
subscriptions, and an array in `operations` is a batch that follows
`HttpOptions.batching`; a map path in a batch starts with the item's index,
as in `0.variables.file`. Without `HttpOptions.uploads`, a `multipart/form-data`
body is refused with `415` (`GQL421`).

## Limits

`UploadLimits` has safe defaults and every refusal is a transport error
before the pipeline, so no context is built and no resolver runs:

- `maxRequestBytes` (20 MiB) bounds the whole body, by `content-length`
  first and by a running count of the bytes that arrive, and `413` `GQL441`
  refuses more. The body must also arrive within `HttpOptions.bodyTimeout`
  (`408`, `GQL427`).
- `maxFieldBytes` (1 MiB) bounds each of `operations` and `map`; the JSON is
  parsed with `HttpOptions.maxJsonDepth`, and a field that is not valid JSON is
  `400` `GQL440`.
- `maxFileBytes` (5 MiB) bounds each file; the file is cut off while it
  streams, the storage drops what it wrote, and the answer is `413` `GQL441`.
- `maxFiles` (10) bounds the keys of the map and, separately, the paths it
  names; more is `413` `GQL442`, so one part named by many paths cannot
  multiply a request.

- The headers of one part may take 8 KiB (`413` `GQL441`): `package:mime`
  buffers a header whole, so the bytes are counted before the parser sees
  them.
- A file name may have 255 characters and a media type 127; more is `400`
  `GQL440`.

Anything else wrong with the structure is `400` `GQL440`: no boundary,
`operations` and `map` out of order, a map that is not an object of lists of
paths, a path that does not name a `null` inside `variables`, a part the map
does not name, a file the map names that never arrives, a malformed part.

## CSRF

A browser sends `multipart/form-data` across sites without a preflight, so
the handler applies the server's `CsrfPrevention` before it reads a single
byte: a request that passes neither the content-type rule nor a custom header
is refused with `403` (`GQL403`) and no file is written. With the production
profile the client must send a non-empty header such as
`graphql-require-preflight` or `apollo-require-preflight`; Apollo's upload
link sends the second. With `ServerProfile.development` CSRF prevention is on
too, so the program above sends a header.

## Storage

`MemoryUploadStorage`, the default, keeps each file in memory, which is right
for small files and tests. Anything larger belongs on disk or in an object
store, and you write that storage yourself.

The file name and the media type that reach `store` are what the client wrote:
unchecked text of at most 255 and 127 characters. A storage must generate its
own names and never use the client's name as a path. This sketch, for a host
that has `dart:io` (this package does not), shows the shape:

```text
final class TemporaryFileStorage implements UploadStorage {
  TemporaryFileStorage(this.directory);

  final Directory directory;

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) async {
    // Its own name: a random one, never `filename`.
    final file = File('${directory.path}/${randomName()}');
    try {
      await content.pipe(file.openWrite());
    } on Exception {
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    return FileUpload(file, filename, mediaType);
  }

  @override
  Future<void> release(Upload upload) async {
    if (upload is FileUpload && upload.file.existsSync()) {
      await upload.file.delete();
    }
  }
}
```

An `UploadStorage` has two methods. `store` receives the content of one file
as a stream. When that stream fails, which is how a file over `maxFileBytes`
is reported, drop what was written and let the error through. `release` is
called once per stored upload, after the response is built, whatever happened
to the request, and must not throw for an upload it does not know; an
exception it throws is reported to `HttpOptions.onError` and does not change
the response, and the other uploads are still released.

A storage that throws from `store` (a full disk, a lost connection to the
object store) is a fault of the server, not of the request: the answer is
`500` `GQL330`, `HttpOptions.onError` sees the exception, and the files already
stored are released. Only the failure of the file's content, which the
storage lets through, is the client's.

This program stores a file by hand, as the reader does for each part:

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  const storage = MemoryUploadStorage();
  final upload = await storage.store(
    'notes.txt',
    'text/plain',
    Stream.value(utf8.encode('hello')),
  );
  print('${upload.filename} ${upload.mediaType} ${upload.length}');
  print(utf8.decode(await upload.openRead().expand((chunk) => chunk).toList()));
  await storage.release(upload);
}
```

It prints:

```text
notes.txt text/plain 5
hello
```

## Reading a file

An `Upload` is valid only during the request. The storage may delete the file
once the response is built, so read it in the resolver, before it returns,
and keep neither the `Upload` nor its stream.
