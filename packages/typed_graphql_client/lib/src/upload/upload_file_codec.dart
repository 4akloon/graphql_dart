import 'package:typed_graphql/typed_graphql.dart';

import 'upload_file.dart';

/// The codec of the `Upload` scalar: it writes a file as its marker, which
/// `HttpLink` (M11b) will replace with the file itself (R8.4).
///
/// Map the scalar in `typed_graphql.yaml`:
///
/// ```text
/// scalars:
///   Upload:
///     type: package:typed_graphql_client/typed_graphql_client.dart#UploadFile
///     codec: package:typed_graphql_client/typed_graphql_client.dart#UploadFileCodec
/// ```
///
/// A file never comes back in a response, so [decode] always fails.
///
/// {@category upload}
final class const UploadFileCodec() implements ScalarCodec<UploadFile> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<UploadFile> decode(JsonValue json) =>
      const DecodeFailure('Upload cannot be read from a response');

  @override
  JsonValue encode(UploadFile value) => JsonString(value.marker);
}
