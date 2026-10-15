import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_node.dart';
import 'execution_run.dart';
import 'pending_values.dart';
import 'response_path.dart';
import 'serial_fields.dart';

/// Executes the fields collected for an object (September2025 6.2.2
/// "Executing a Selection Set"): in parallel, or one after another for the
/// root fields of a mutation.
final class SelectionExecutor {
  /// Executes for [_run].
  SelectionExecutor(this._run);

  final ExecutionRun _run;

  /// The object of the fields of [node] on [parent], started in order. The
  /// result is null when a field fails at a non-null position: the null
  /// propagates and the fields after it are not started.
  FutureOr<JsonObject?> execute(
    Object? parent,
    PlanNode node,
    ResponsePath path,
    int depth,
  ) {
    final pending = PendingValues();
    for (final field in node.fields) {
      if (_run.reporter.log.isHalted) {
        return pending.abandon();
      }
      final result = _run.fields.execute(parent, field, path, depth);
      if (result == null) {
        return pending.abandon();
      }
      pending.add(result);
    }
    return pending.finishWith((values) => assemble(node, values));
  }

  /// Like [execute], but each field completes before the next one starts.
  FutureOr<JsonObject?> executeSerially(
    Object? parent,
    PlanNode node,
    ResponsePath path,
    int depth,
  ) => SerialFields(_run, parent, node, path, depth).from(0);

  /// The object holding [values] under the response keys of [node].
  static JsonObject assemble(PlanNode node, List<JsonValue> values) =>
      JsonObject({
        for (var i = 0; i < values.length; i++)
          node.fields[i].responseKey: values[i],
      });
}
