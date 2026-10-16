import 'package:typed_graphql/typed_graphql.dart';

import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../upload/upload_files.dart';
import 'persisted_query_run.dart';

/// Sends a hash instead of the document text, which a server that stores
/// persisted documents answers from memory (R8.4; the server side is M6).
///
/// The request goes out with `extensions.persistedQuery` holding the
/// document's SHA-256 and no `query`. In the automatic mode (the default), a
/// server that does not know the hash says `PersistedQueryNotFound` (or
/// `GQL410`) and the link sends the request again with the text and the
/// hash, which the server stores after it validated the text; a server that
/// stores nothing says `PersistedQueryNotSupported` (or `GQL412`) and the
/// link sends the text alone, now and in every later request. With
/// `isAutomatic: false` (trusted documents) the hash alone is always sent
/// and whatever comes back is delivered, such as the server's `GQL415` for an
/// unknown document.
///
/// It applies to queries and mutations; a subscription and a request with
/// `UploadFiles` pass through unchanged. A second miss after the text was
/// sent is an answer and is delivered, not answered again. A stream error
/// from the links below reaches the caller untouched.
///
/// {@category policy}
final class PersistedQueryLink extends Link {
  /// Creates a link in the automatic mode, or in the trusted mode when
  /// [isAutomatic] is false.
  PersistedQueryLink({this.isAutomatic = true});

  /// Whether the link falls back to the text when the server does not know
  /// the hash.
  final bool isAutomatic;

  bool _isSupportedByServer = true;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (!_isSupportedByServer || !_isApplicable(request)) {
      return forward(request);
    }
    return PersistedQueryRun(
      request,
      forward,
      isAutomatic: isAutomatic,
      onNotSupported: () => _isSupportedByServer = false,
    ).results;
  }

  bool _isApplicable(LinkRequest request) =>
      request.type != OperationType.subscription &&
      request.context.entry<UploadFiles>() == null;
}
