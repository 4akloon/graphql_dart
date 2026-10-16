# Uploads

A GraphQL multipart request carries files next to the operation (R5.6). This
guide describes the pieces a schema needs; the handler that reads multipart
requests comes with the HTTP transport.

## The pieces

- `Upload` is what a resolver reads: `filename`, `mediaType`, `length` and
  `openRead()`.
- `UploadStorage` is where a file waits until the response is built:
  `store` takes the file's bytes and returns an `Upload`, `release` frees it.
  `MemoryUploadStorage` keeps files in memory.
- `UploadLimits` bounds a request: `maxFiles`, `maxFileBytes`,
  `maxRequestBytes` and `maxFieldBytes`.
- `Uploads` holds a storage and the limits, and gives the schema its scalar.

## The scalar

One `Uploads` value is shared by the schema and the handler. The schema
declares the scalar with its codec:

```text
final uploads = Uploads();
final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
```

The scalar is input only: encoding an `Upload` is an `ArgumentError`. A
variable of type `Upload` reaches the resolver as the `Upload` the request
carried; any other value is a coercion error, "Upload value is not a file of
this request."

A storage keeps a file's bytes and hands back an `Upload`. This program stores
a file by hand, as the multipart reader does for each part:

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

## Writing a storage

`store` receives the content of one file as a stream. When that stream fails,
which is how a file over `maxFileBytes` is reported, drop what was written
and let the error through. `release` is called once per stored upload, after
the response is built, and must not throw for an upload it does not know.
