import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'guarded_start.dart';
import 'persisted_query_errors.dart';

/// The attempts of one request for `PersistedQueryLink`: the hash alone,
/// then, when the server asks for it, the text.
final class PersistedQueryRun {
  /// Creates the run of [_request]; nothing starts before the first
  /// listener. [onNotSupported] tells the link to stop sending hashes.
  PersistedQueryRun(
    this._request,
    this._forward, {
    required this.isAutomatic,
    required this.onNotSupported,
  }) {
    _controller.onListen = _sendHashAlone;
    _controller.onCancel = _stop;
  }

  final LinkRequest _request;
  final NextLink _forward;

  /// Whether a miss is answered with the text; false for trusted documents.
  final bool isAutomatic;

  /// Called when the server says it stores no queries.
  final void Function() onNotSupported;
  final PersistedQueryErrors _errors = const PersistedQueryErrors();
  final StreamController<LinkResult> _controller =
      StreamController<LinkResult>();

  StreamSubscription<LinkResult>? _subscription;

  /// What the caller listens to: the answers of the attempt that was kept.
  Stream<LinkResult> get results => _controller.stream;

  void _sendHashAlone() => _listenTo(
    _withHash().withDocumentText(sendsDocumentText: false),
    onResult: _onFirstResult,
  );

  void _listenTo(
    LinkRequest request, {
    required void Function(LinkResult result) onResult,
  }) {
    _subscription = const GuardedStart().listen<LinkResult>(
      () => _forward(request),
      convert: (result) => result,
      onData: onResult,
      onError: _controller.addError,
      onDone: () {
        _subscription = null;
        unawaited(_controller.close());
      },
    );
  }

  void _onFirstResult(LinkResult result) {
    if (isAutomatic && _errors.isNotFound(result)) {
      _resend(_withHash());
    } else if (isAutomatic && _errors.isNotSupported(result)) {
      onNotSupported();
      _resend(_request);
    } else {
      _controller.add(result);
    }
  }

  /// Drops the hash-only attempt and sends [request], whose answer is the
  /// one delivered.
  void _resend(LinkRequest request) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _listenTo(request, onResult: _controller.add);
  }

  /// The request with `extensions.persistedQuery` added to its extensions.
  LinkRequest _withHash() => _request.withExtensions(
    JsonObject({
      ...?_request.extensions?.fields,
      'persistedQuery': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString(_request.document.sha256),
      }),
    }),
  );

  Future<void> _stop() {
    final cancelled = _subscription?.cancel();
    _subscription = null;
    return cancelled ?? Future<void>.value();
  }
}
