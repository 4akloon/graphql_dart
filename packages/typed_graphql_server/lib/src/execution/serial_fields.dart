import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_node.dart';
import 'execution_run.dart';
import 'pending_values.dart';
import 'response_path.dart';
import 'selection_executor.dart';

/// Runs the fields of one node one after another (September2025 6.2.2,
/// "Executing a Selection Set Serially"): a field starts when the one before
/// it has completed.
final class SerialFields {
  /// Prepares the serial run of [node] on [parent].
  SerialFields(this._run, this._parent, this._node, this._path, this._depth);

  final ExecutionRun _run;
  final Object? _parent;
  final PlanNode _node;
  final ResponsePath _path;
  final int _depth;
  final PendingValues _values = PendingValues();

  /// Runs the fields from position [index]; synchronous while the fields
  /// are. Null when a field fails at a non-null position or the execution
  /// halts: the fields after it are not started.
  FutureOr<JsonObject?> from(int index) {
    final fields = _node.fields;
    for (var i = index; i < fields.length; i++) {
      if (_run.reporter.log.isHalted) {
        return null;
      }
      final result = _run.fields.execute(
        _parent,
        fields[i],
        _path,
        _depth,
        i,
      );
      if (result is Future<JsonValue?>) {
        return result.then((resolved) => _after(i, resolved));
      }
      if (result == null) {
        return null;
      }
      _values.add(result);
    }
    return _values.finishWith((values) {
      return SelectionExecutor.assemble(_node, values);
    });
  }

  FutureOr<JsonObject?> _after(int index, JsonValue? resolved) {
    if (resolved == null) {
      return null;
    }
    _values.add(resolved);
    return from(index + 1);
  }
}
