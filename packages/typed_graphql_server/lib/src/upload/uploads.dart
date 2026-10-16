import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'memory_upload_storage.dart';
import 'upload.dart';
import 'upload_codec.dart';
import 'upload_limits.dart';
import 'upload_registry.dart';
import 'upload_storage.dart';

/// The configuration of multipart uploads: where files wait, how large a
/// request may be, and the `Upload` scalar that hands a file to a resolver.
///
/// One value wires both sides: the schema declares the scalar with [codec]
/// and the HTTP handler reads multipart requests with `HttpOptions.uploads`.
///
/// {@category upload}
final class Uploads {
  /// Creates the configuration; files are kept in memory unless a [storage]
  /// is given.
  Uploads({
    this.storage = const MemoryUploadStorage(),
    this.limits = const UploadLimits(),
  });

  /// The name of the scalar in the schema.
  static const String scalarName = 'Upload';

  /// Where the files of a request wait.
  final UploadStorage storage;

  /// The sizes a request may reach.
  final UploadLimits limits;

  /// The tokens of the requests being served, shared with [codec].
  @internal
  final UploadRegistry registry = UploadRegistry();

  /// The codec of the `Upload` scalar, for input only: encoding is an
  /// [ArgumentError].
  ScalarCodec<Upload> get codec => UploadCodec(registry);
}
