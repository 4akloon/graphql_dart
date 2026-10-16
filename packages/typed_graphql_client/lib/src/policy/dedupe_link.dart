import 'package:typed_graphql/typed_graphql.dart';

import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../link/request_headers.dart';
import '../upload/upload_files.dart';
import 'shared_request.dart';

/// Lets identical queries that are in flight at the same time share one
/// forwarded request (R8.4).
///
/// Two queries are identical when their bodies (document, variables and
/// extensions, compared as JSON values) and their [RequestHeaders] are equal.
/// Each caller gets the shared result through its own stream. A caller that
/// cancels leaves the others their result; the forwarded request is cancelled
/// when the last caller cancels. The sharing ends at the first result, so a
/// query sent later goes out again: this link is not a cache (the normalized
/// cache arrives with M12).
///
/// The bodies are compared as `JsonObject`s, which ignore the order of keys:
/// variables written in another order are still identical. A stream error from
/// the links below reaches every caller untouched, and a forward that throws
/// is the error of the callers that joined.
///
/// Mutations, subscriptions and requests with `UploadFiles` pass through.
///
/// {@category policy}
final class DedupeLink extends Link {
  /// Creates a link with nothing in flight.
  DedupeLink();

  final Map<JsonValue, SharedRequest> _inFlight = {};

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (!_isShareable(request)) {
      return forward(request);
    }
    final key = _keyOf(request);
    // The entry is found when the caller listens, not when it asks, so a
    // caller that listens late still joins a request that is in flight.
    return Stream<LinkResult>.multi((caller) {
      final shared = _inFlight[key] ??= SharedRequest(
        request,
        forward,
        () => _inFlight.remove(key),
      );
      shared.join(caller);
    });
  }

  bool _isShareable(LinkRequest request) =>
      request.type == OperationType.query &&
      request.context.entry<UploadFiles>() == null;

  JsonValue _keyOf(LinkRequest request) {
    final headers = request.context.entry<RequestHeaders>()?.values ?? const {};
    return JsonArray([
      request.body.toJson(),
      JsonObject({
        for (final MapEntry(:key, :value) in headers.entries)
          key: JsonString(value),
      }),
    ]);
  }
}
