import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/csrf_prevention.dart';
import '../server/request_info.dart';
import '../upload/boundary_syntax.dart';
import '../upload/multipart_reader.dart';
import '../upload/multipart_result.dart';
import '../upload/uploads.dart';
import 'content_type.dart';
import 'http_options.dart';
import 'http_request_data.dart';
import 'request_decoding.dart';

/// Reads the `multipart/form-data` body of a `POST` after the checks that
/// cost nothing: CSRF prevention, the boundary and the declared length (spec
/// section 8).
@internal
final class MultipartPost {
  /// Creates the reader for a handler configured with [options], whose files
  /// go where [uploads] says and which [csrfPrevention] guards, if it is not
  /// null; a release that fails is handed to [onReleaseError].
  const MultipartPost(
    this.options,
    this.uploads,
    this.csrfPrevention,
    this.onReleaseError,
  );

  /// The depth and time limits to apply.
  final HttpOptions options;

  /// The storage and the size limits.
  final Uploads uploads;

  /// The rule a request passes before its body is read, or null.
  final CsrfPrevention? csrfPrevention;

  /// Where the failure of a release is reported.
  final void Function(Object error, StackTrace stackTrace) onReleaseError;

  /// Whether [request] says its body is `multipart/form-data`.
  bool isMultipart(HttpRequestData request) =>
      ContentType.parse(request.header('content-type'))?.mediaType ==
      'multipart/form-data';

  /// Reads the body of [request]; the body is not touched when the CSRF rule,
  /// the boundary or the declared length already refuse the request.
  ///
  /// The rule runs here as well as in the pipeline because a forged
  /// cross-site form must not cost a single file write (deviation 8).
  Future<MultipartResult> read(HttpRequestData request) {
    final prevention = csrfPrevention;
    if (prevention != null && !prevention.allows(_info(request))) {
      return _refused(
        403,
        DiagnosticCode.csrfRequestBlocked,
        prevention.refusal,
      );
    }
    final boundary =
        ContentType.parse(
          request.header('content-type'),
        )?.parameters['boundary'] ??
        '';
    final boundaryRefusal = _refusalOfBoundary(boundary);
    if (boundaryRefusal != null) return boundaryRefusal;
    final length = int.tryParse(request.header('content-length')?.trim() ?? '');
    final maxBytes = uploads.limits.maxRequestBytes;
    if (length != null && length > maxBytes) {
      return _refused(
        413,
        DiagnosticCode.uploadTooLarge,
        'The request body is larger than $maxBytes bytes.',
      );
    }
    return MultipartReader(
      uploads,
      maxJsonDepth: options.maxJsonDepth,
      bodyTimeout: options.bodyTimeout,
      onReleaseError: onReleaseError,
    ).read(request.body, boundary, cancelSignal: request.cancelSignal);
  }

  // The syntax is RFC 2046's: package:mime and the header scanner read a
  // boundary byte by byte, so a character outside it could make them disagree.
  Future<MultipartResult>? _refusalOfBoundary(String boundary) {
    if (boundary.isEmpty) {
      return _refused(
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The multipart request has no boundary.',
      );
    }
    if (const BoundarySyntax().allows(boundary)) return null;
    return _refused(
      400,
      DiagnosticCode.malformedMultipartRequest,
      'The multipart boundary is not valid.',
    );
  }

  RequestInfo _info(HttpRequestData request) => RequestInfo(
    method: request.method,
    uri: request.uri,
    headers: request.headers,
    source: request.source,
  );

  Future<MultipartResult> _refused(
    int status,
    DiagnosticCode code,
    String message,
  ) async => MultipartRefusal(DecodingRefusal(status, code, message));
}
