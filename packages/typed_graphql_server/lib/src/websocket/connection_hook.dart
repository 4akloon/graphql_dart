import 'dart:async';

import '../server/request_info.dart';
import 'connection_decision.dart';

/// Decides whether a graphql-ws connection is accepted, when its
/// `connection_init` arrives.
///
/// [info] is the upgrade request's, with `RequestInfo.connectionParams` set
/// to the message's payload, so the hook may read a token there (or a header
/// or cookie of the upgrade) and refuse. A throw closes the connection with
/// `4500` and sends the client nothing of the error.
///
/// {@category websocket}
typedef ConnectionHook = FutureOr<ConnectionDecision> Function(
  RequestInfo info,
);
