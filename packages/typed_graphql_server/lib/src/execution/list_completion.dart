import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'execution_run.dart';
import 'pending_values.dart';

/// Completes the value of a list type (September2025 6.4.3): each item by
/// the list's item type, at the item's index.
final class ListCompletion {
  /// Completes for [_run].
  ListCompletion(this._run);

  final ExecutionRun _run;

  /// The array of the items of [value] for [type], or Dart `null` when an
  /// item fails at a non-null position or [value] is not an [Iterable].
  FutureOr<JsonValue?> complete(
    ListType type,
    Object value,
    CompletionSite site,
  ) {
    if (value is! Iterable<Object?>) {
      _run.reporter.fieldError(
        DiagnosticCode.unexpectedValue,
        'Expected Iterable, but did not find one for field '
        '"${site.fieldLabel}".',
        site,
      );
      return null;
    }
    final pending = PendingValues();
    try {
      var index = 0;
      for (final item in value) {
        final completed = _run.settle(
          type.type,
          _run.values.complete(type.type, item, site.itemAt(index)),
        );
        if (completed == null || _run.reporter.log.isHalted) {
          return pending.abandon();
        }
        pending.add(completed);
        index++;
      }
    } on Object catch (error, stackTrace) {
      // A lazy iterable throws while it is walked.
      _run.reporter.thrown(error, stackTrace, site);
      return pending.abandon();
    }
    return pending.finishWith(JsonArray.new);
  }
}
