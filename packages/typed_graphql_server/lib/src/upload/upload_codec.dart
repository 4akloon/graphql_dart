import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'upload.dart';
import 'upload_registry.dart';

/// The codec of the `Upload` scalar: it turns the token the multipart reader
/// wrote into a variable back into the file.
@internal
final class UploadCodec implements ScalarCodec<Upload> {
  /// Creates a codec that looks tokens up in [registry].
  const UploadCodec(this.registry);

  /// The uploads of the requests being served.
  final UploadRegistry registry;

  @override
  DecodeResult<Upload> decode(JsonValue json) {
    if (json is JsonString) {
      final upload = registry.lookup(json.value);
      if (upload != null) return DecodeSuccess(upload);
    }
    return const DecodeFailure('Upload value is not a file of this request.');
  }

  @override
  JsonValue encode(Upload value) => throw ArgumentError.value(
    value,
    'value',
    'Upload is an input-only scalar.',
  );
}
