import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/request_decoding.dart';
import 'stored_uploads.dart';

/// What reading a multipart request gave: the operations with their files, or
/// the refusal to write.
@internal
sealed class MultipartResult {
  /// Creates a result.
  const MultipartResult();
}

/// A request whose parts were all read and stored.
@internal
final class MultipartContent extends MultipartResult {
  /// Creates the result of [operations] and the files [stored] for it.
  const MultipartContent(this.operations, this.stored);

  /// The `operations` value, with a token in the place of every file.
  final JsonValue operations;

  /// The files of the request; the caller releases them when the response is
  /// built.
  final StoredUploads stored;
}

/// A request the transport refuses; nothing it stored is left.
@internal
final class MultipartRefusal extends MultipartResult {
  /// Creates the result holding [refusal].
  const MultipartRefusal(this.refusal);

  /// The status, code and message to answer with.
  final DecodingRefusal refusal;
}
