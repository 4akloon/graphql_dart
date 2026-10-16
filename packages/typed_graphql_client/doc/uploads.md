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
