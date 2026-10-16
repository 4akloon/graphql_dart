import 'dart:async';

/// Reads the current token and renews it for `AuthLink`, with one refresh
/// in flight at a time.
final class TokenRenewal {
  /// Creates the renewal over the caller's [_token] and [_refresh].
  TokenRenewal(this._token, this._refresh);

  final FutureOr<String?> Function() _token;
  final Future<String?> Function()? _refresh;
  Future<String?>? _refreshing;
  int _refreshCount = 0;
  String? _lastRefreshed;

  /// Whether a refresh callback was given.
  bool get canRefresh => _refresh != null;

  /// The token to send now, or null for none.
  Future<String?> current() async => _token();

  /// The token to send again after [sentToken] was refused: the result of a
  /// refresh that is running or that finished while this call read the
  /// token, else the current token when it is another non-null one (someone
  /// else renewed it), else the result of a new refresh, which every caller
  /// waiting at the same time shares. Null when there is nothing better to
  /// send.
  Future<String?> renewed(String? sentToken) async {
    final inFlight = _refreshing;
    if (inFlight != null) {
      return inFlight;
    }
    // A slow read may return a token from before a refresh that finished
    // meanwhile; the count tells that a refresh happened since this call began.
    final countAtStart = _refreshCount;
    final latest = await current();
    final startedMeanwhile = _refreshing;
    if (startedMeanwhile != null) {
      return startedMeanwhile;
    }
    final refreshed = _lastRefreshed;
    if (_refreshCount != countAtStart && refreshed != null) {
      return refreshed;
    }
    if (latest != null && latest != sentToken) {
      return latest;
    }
    return _refreshOnce();
  }

  Future<String?> _refreshOnce() {
    final refresh = _refresh;
    if (refresh == null) {
      return Future<String?>.value();
    }
    _refreshCount++;
    return _refreshing ??= refresh()
        .then(_remember, onError: _forget)
        .whenComplete(() {
          _refreshing = null;
        });
  }

  // A null token or a failure clears it: the last token was refused, and
  // a caller that read the count meanwhile must not be given it again.
  String? _remember(String? token) {
    _lastRefreshed = token;
    return token;
  }

  String? _forget(Object error, StackTrace stackTrace) {
    _lastRefreshed = null;
    Error.throwWithStackTrace(error, stackTrace);
  }
}
