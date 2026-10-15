import 'dart:async';

import 'request_info.dart';

/// Builds the context of one executed request.
///
/// It runs once per executed request, after the document is accepted and
/// every limit has passed, so a refused request never builds a context.
///
/// {@category server}
typedef ContextFactory<C> = FutureOr<C> Function(RequestInfo request);
