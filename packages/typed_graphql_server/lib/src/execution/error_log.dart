import 'package:typed_graphql/typed_graphql.dart';

import 'error_behavior.dart';

/// The errors of one execution in the order they were recorded, and whether
/// the execution has halted.
final class ErrorLog {
  /// Creates an empty log that applies [behavior].
  ErrorLog(this.behavior);

  /// What an error does to the execution.
  final ErrorBehavior behavior;

  final List<_Entry> _entries = [];

  /// The errors recorded so far in document order: by the position of their
  /// path (see `ResponsePath.orderKey`), the order of recording for equal
  /// positions.
  List<GraphQLError> get errors {
    final sorted = [..._entries]..sort(_Entry.compare);
    return [for (final entry in sorted) entry.error];
  }

  /// The error that ended the execution; null while it runs on.
  GraphQLError? haltError;

  /// Whether the execution has ended: nothing more is started or recorded.
  bool get isHalted => haltError != null;

  /// Records [error] found at the document position [order]; under
  /// [ErrorBehavior.halt] it also ends the execution.
  void record(GraphQLError error, [List<int> order = const []]) {
    if (isHalted) {
      return;
    }
    _entries.add(_Entry(error, order, _entries.length));
    if (behavior == ErrorBehavior.halt) {
      haltError = error;
    }
  }

  /// Ends the execution with [error], whatever the behaviour.
  void halt(GraphQLError error) {
    if (isHalted) {
      return;
    }
    _entries.add(_Entry(error, const [], _entries.length));
    haltError = error;
  }
}

class _Entry {
  _Entry(this.error, this.order, this.sequence);

  final GraphQLError error;
  final List<int> order;
  final int sequence;

  // Sort is not stable, so the sequence breaks ties.
  static int compare(_Entry a, _Entry b) {
    final shared = a.order.length < b.order.length
        ? a.order.length
        : b.order.length;
    for (var i = 0; i < shared; i++) {
      if (a.order[i] != b.order[i]) {
        return a.order[i].compareTo(b.order[i]);
      }
    }
    if (a.order.length != b.order.length) {
      return a.order.length.compareTo(b.order.length);
    }
    return a.sequence.compareTo(b.sequence);
  }
}
