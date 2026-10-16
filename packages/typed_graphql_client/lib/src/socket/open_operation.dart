import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_request.dart';
import '../link/link_result.dart';

/// One request to a `WebSocketLink` that has not ended: its id on the
/// socket, the stream its caller listens to, and whether the current socket
/// has been told to run it.
@internal
final class OpenOperation {
  /// Creates the operation; [onListen] and [onCancel] run when the caller
  /// listens to and cancels the stream.
  OpenOperation(
    this.id,
    this.request, {
    required void Function(OpenOperation operation) onListen,
    required void Function(OpenOperation operation) onCancel,
  }) {
    controller = StreamController<LinkResult>(
      onListen: () => onListen(this),
      onCancel: () => onCancel(this),
    );
  }

  /// The id the protocol knows the operation by; it stays the same across
  /// reconnections, as a new socket has no operations.
  final String id;

  /// The request, kept to subscribe again after a reconnection.
  final LinkRequest request;

  /// The stream the caller listens to.
  // `late`: the callbacks refer to this operation, so the constructor body
  // makes the controller, before anything can read it.
  late final StreamController<LinkResult> controller;

  /// Whether the current socket has been sent the `subscribe`.
  bool isSent = false;

  /// Whether the request is a mutation, which is never sent twice.
  bool get isMutation => request.type == OperationType.mutation;

  /// Gives the caller [last], if any, and ends its stream.
  void end([LinkResult? last]) {
    if (last != null) {
      controller.add(last);
    }
    unawaited(controller.close());
  }
}
