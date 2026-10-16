import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../link/link_result.dart';
import 'open_operation.dart';

/// The operations of a `WebSocketLink` that have not ended, by id.
///
/// It holds one entry per active operation and nothing per message, so a
/// flood of results for unknown ids costs a lookup each (spec section 11).
@internal
final class SocketOperations {
  final Map<String, OpenOperation> _open = {};
  int _lastId = 0;

  /// Whether no operation is open.
  bool get isEmpty => _open.isEmpty;

  /// The open operations, in the order they were added.
  List<OpenOperation> get all => List.of(_open.values);

  /// The id for the next operation: `"1"`, `"2"`, ... for the link's life.
  String nextId() => '${++_lastId}';

  /// Registers [operation] as open.
  void add(OpenOperation operation) => _open[operation.id] = operation;

  /// Forgets the operation [id]; whether it was open.
  bool remove(String id) => _open.remove(id) != null;

  /// Gives the operation [id], if open, one more result.
  void emit(String id, LinkResult result) => _open[id]?.controller.add(result);

  /// Ends the operation [id], if open, after [last] if given.
  void finish(String id, {LinkResult? last}) {
    _open.remove(id)?.end(last);
  }

  /// Ends every operation with [failure].
  void failAll(ClientFailure failure) => _failWhere(failure, (_) => true);

  /// Ends the mutations the socket was told to run with [failure]: a
  /// mutation is never sent twice, as the server may have run it.
  void failSentMutations(ClientFailure failure) => _failWhere(
    failure,
    (operation) => operation.isMutation && operation.isSent,
  );

  /// Marks every operation as not sent, for a new socket.
  void markAllUnsent() {
    for (final operation in _open.values) {
      operation.isSent = false;
    }
  }

  void _failWhere(
    ClientFailure failure,
    bool Function(OpenOperation operation) test,
  ) {
    for (final operation in all.where(test)) {
      _open.remove(operation.id);
      operation.end(LinkFailure(failure));
    }
  }
}
