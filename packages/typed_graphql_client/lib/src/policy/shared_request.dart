import 'dart:async';

import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'guarded_start.dart';

/// One forwarded request and the callers of `DedupeLink` waiting for its
/// answer.
final class SharedRequest {
  /// Creates the request to forward when the first caller joins;
  /// [_onEnded] removes it from the link's table, once.
  SharedRequest(this._request, this._forward, this._onEnded);

  final LinkRequest _request;
  final NextLink _forward;
  final void Function() _onEnded;
  final List<MultiStreamController<LinkResult>> _callers = [];
  StreamSubscription<LinkResult>? _upstream;
  bool _isListed = true;
  bool _isStarted = false;
  bool _isEnded = false;

  /// Adds [caller] to those waiting; the first one starts the request. A
  /// forward that throws is the error of every caller, and the request is
  /// no longer shared.
  void join(MultiStreamController<LinkResult> caller) {
    _callers.add(caller);
    caller.onCancel = () => _leave(caller);
    if (_isStarted) {
      return;
    }
    _isStarted = true;
    _upstream = const GuardedStart().listen<LinkResult>(
      () => _forward(_request),
      convert: (result) => result,
      onData: _onResult,
      onError: _onError,
      onDone: _onDone,
    );
    // A source that ends inside `listen` has already run `_onDone`, which
    // could not clear the field before this assignment.
    if (_isEnded) {
      _upstream = null;
    }
  }

  void _onResult(LinkResult result) {
    _unlist();
    for (final caller in List.of(_callers)) {
      caller.add(result);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _unlist();
    for (final caller in List.of(_callers)) {
      caller.addError(error, stackTrace);
    }
  }

  void _onDone() {
    _isEnded = true;
    _unlist();
    for (final caller in List.of(_callers)) {
      unawaited(caller.close());
    }
    _callers.clear();
    _upstream = null;
  }

  Future<void>? _leave(MultiStreamController<LinkResult> caller) {
    _callers.remove(caller);
    if (_callers.isNotEmpty) {
      return null;
    }
    _unlist();
    final cancelled = _upstream?.cancel();
    _upstream = null;
    return cancelled;
  }

  void _unlist() {
    if (_isListed) {
      _isListed = false;
      _onEnded();
    }
  }
}
