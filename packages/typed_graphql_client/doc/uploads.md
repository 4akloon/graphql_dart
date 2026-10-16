# Uploads

A GraphQL server that follows the multipart request specification takes
files as values of the `Upload` scalar. The client sends them in three
steps.

## Mapping the scalar

Map `Upload` in `typed_graphql.yaml`, so the generated variables hold an
`UploadFile`:

```text
scalars:
  Upload:
    type: package:typed_graphql_client/typed_graphql_client.dart#UploadFile
    codec: package:typed_graphql_client/typed_graphql_client.dart#UploadFileCodec
```

`UploadFileCodec` writes a file as its `marker`, a string unique to the
`UploadFile` object, and never reads one: a file does not come back in a
response.

## Files and their list

`UploadFile.fromBytes(bytes, filename:)` holds a copy of the bytes;
`UploadFile.fromStream(open, length:, filename:)` calls `open` for each
attempt, so a retried request sends the file again. Both take a
`contentType` (default `application/octet-stream`).

The variables of a generated operation are JSON, where a file is only its
marker, so the caller lists the files of a request in its context:

```text
final avatar = UploadFile.fromBytes(bytes, filename: 'avatar.png', contentType: 'image/png');
await client.mutate(
  SetAvatarMutation(file: avatar),
  context: LinkContext([UploadFiles([avatar])]),
);
```

A link that cannot send files answers a request with `UploadFiles` with an
`UnsupportedOperation` (`GQL468`).

## Sending files over HTTP

`HttpLink` sends a request with `UploadFiles` as a `multipart/form-data`
`POST`, even a query when the link uses `GET` for queries. The
`operations` part is the request with each marker replaced by `null`, the
`map` part says which variables each file fills, and each file follows as
its own part. The program below prints what an in-memory server receives,
with the random boundary replaced:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class UploadMutation extends GraphQLMutation<bool> {
  const UploadMutation(this.file);

  final UploadFile file;

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Upload',
    type: OperationType.mutation,
    text: r'mutation Upload($file:Upload!){upload(file:$file)}',
    sha256: 'a5525ac82c47deb5ec28d3583a98d2bd0f8a09a9a49dc51d46ff648a7fe63a2c',
  );

  @override
  JsonObject get variablesJson =>
      JsonObject({'file': const UploadFileCodec().encode(file)});

  @override
  DecodeResult<bool> decodeData(JsonObject data) => switch (data['upload']) {
    JsonBool(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a boolean', path: [PathKey('upload')]),
  };
}

final class InMemoryServer implements HttpTransport {
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final type = request.headers['content-type'] ?? '';
    final boundary = type.substring(type.indexOf('=') + 1);
    final body = await utf8.decodeStream(request.body ?? const Stream.empty());
    print(type.replaceAll(boundary, 'BOUNDARY'));
    print(body.replaceAll(boundary, 'BOUNDARY').replaceAll('\r\n', '\n'));
    return TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/graphql-response+json'},
      body: Stream.value(utf8.encode('{"data":{"upload":true}}')),
    );
  }
}

Future<void> main() async {
  final client = GraphQLClient(
    link: HttpLink(
      uri: Uri.parse('https://example.com/graphql'),
      transport: InMemoryServer(),
    ),
  );
  final note = UploadFile.fromBytes(
    utf8.encode('hello'),
    filename: 'note.txt',
    contentType: 'text/plain',
  );
  final response = await client.mutate(
    UploadMutation(note),
    context: LinkContext([
      UploadFiles([note]),
    ]),
  );
  print(response is GraphQLData<bool> ? 'uploaded' : 'failed: $response');
}
```

It prints:

```text
multipart/form-data; boundary=BOUNDARY
--BOUNDARY
Content-Disposition: form-data; name="operations"
Content-Type: application/json

{"query":"mutation Upload($file:Upload!){upload(file:$file)}","operationName":"Upload","variables":{"file":null}}
--BOUNDARY
Content-Disposition: form-data; name="map"
Content-Type: application/json

{"0":["variables.file"]}
--BOUNDARY
Content-Disposition: form-data; name="0"; filename="note.txt"
Content-Type: text/plain

hello
--BOUNDARY--

uploaded
```

The request carries `graphql-require-preflight: true`, because a browser
form can send the same content type from another site and servers with
CSRF prevention refuse multipart requests without it. A marker that the
`UploadFiles` entry does not list, or a listed file no variable holds, is
an `ArgumentError`: a mistake in the calling code, not in the answer.
