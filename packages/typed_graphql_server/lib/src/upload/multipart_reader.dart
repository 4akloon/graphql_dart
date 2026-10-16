import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../http/request_decoding.dart';
import 'body_failure.dart';
import 'byte_limit.dart';
import 'byte_limit_exceeded.dart';
import 'multipart_result.dart';
import 'multipart_run.dart';
import 'part_header_scanner.dart';
import 'part_header_too_large.dart';
import 'storage_failure.dart';
import 'uploads.dart';
import 'watched_body.dart';

/// Reads the body of a `multipart/form-data` request as the GraphQL multipart
/// request specification defines it (spec section 8 of M7): `operations`,
/// `map`, then the files, each file streamed into the storage of [uploads]
/// within the limits.
///
/// Whatever goes wrong with the request, the result is a refusal and nothing
/// it stored is left; whatever goes wrong with the body, the body is
/// cancelled.
@internal
final class MultipartReader {
  /// Creates a reader that stores files as [uploads] says, parses JSON nested
  /// at most [maxJsonDepth] deep and waits at most [bodyTimeout] for the
  /// whole body; a release that fails is handed to [onReleaseError].
  const MultipartReader(
    this.uploads, {
    required this.maxJsonDepth,
    required this.bodyTimeout,
    required this.onReleaseError,
  });

  /// The most bytes the headers of one part may take.
  static const int maxHeaderBytes = 8192;

  /// The storage and the limits.
  final Uploads uploads;

  /// The deepest nesting of arrays and objects accepted in a JSON field.
  final int maxJsonDepth;

  /// How long the whole body may take to arrive.
  final Duration bodyTimeout;

  /// Where the failure of a release is reported.
  final void Function(Object error, StackTrace stackTrace) onReleaseError;

  /// Reads [body], whose parts are separated by [boundary]; the body fails
  /// when [cancelSignal] fires.
  ///
  /// The package:mime parser throws on a malformed header inside the zone
  /// that calls it, not into its stream, so the read runs in a guarded zone
  /// whose errors become the failure of the body.
  Future<MultipartResult> read(
    Stream<List<int>> body,
    String boundary, {
    CancelSignal? cancelSignal,
  }) {
    final watch = WatchedBody(
      body,
      ByteLimit(uploads.limits.maxRequestBytes),
      bodyTimeout,
      PartHeaderScanner(boundary, maxHeaderBytes),
      cancelSignal: cancelSignal,
    );
    final completer = Completer<MultipartResult>();
    runZonedGuarded(
      () => _consume(watch, boundary).then(
        completer.complete,
        onError: completer.completeError,
      ),
      (error, stack) => watch.fail(error),
    );
    return completer.future;
  }

  Future<MultipartResult> _consume(WatchedBody watch, String boundary) async {
    final run = MultipartRun(uploads, watch, maxJsonDepth, onReleaseError);
    var isKept = false;
    try {
      final parts = MimeMultipartTransformer(boundary).bind(watch.stream);
      final result = await run.consume(parts);
      isKept = result is MultipartContent;
      return result;
    } on StorageFailure {
      // The server's fault, not the request's: the handler's outermost
      // boundary answers it.
      rethrow;
    } on Exception catch (error, stackTrace) {
      return MultipartRefusal(_refusalFor(error, stackTrace));
    } finally {
      watch.cancel();
      if (!isKept) await run.stored.release();
    }
  }

  // An exception that is none of the failures of a body is a bug of the
  // server, not of the request: it goes up to the handler's boundary.
  DecodingRefusal _refusalFor(
    Exception error,
    StackTrace stackTrace,
  ) => switch (error) {
    ByteLimitExceeded() => DecodingRefusal(
      413,
      DiagnosticCode.uploadTooLarge,
      'The request body is larger than ${uploads.limits.maxRequestBytes} '
      'bytes.',
    ),
    PartHeaderTooLarge() => const DecodingRefusal(
      413,
      DiagnosticCode.uploadTooLarge,
      'A part header is larger than $maxHeaderBytes bytes.',
    ),
    TimeoutException() => DecodingRefusal(
      408,
      DiagnosticCode.requestBodyTimeout,
      'The request body did not arrive within ${bodyTimeout.inMilliseconds} '
      'ms.',
    ),
    MimeMultipartException() || FormatException() => const DecodingRefusal(
      400,
      DiagnosticCode.malformedMultipartRequest,
      'The multipart request is malformed.',
    ),
    BodyFailure() => const DecodingRefusal(
      400,
      DiagnosticCode.malformedRequestBody,
      'The request body could not be read.',
    ),
    _ => Error.throwWithStackTrace(error, stackTrace),
  };
}
