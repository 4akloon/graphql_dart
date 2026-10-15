import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'abstract_resolution.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Completes the value of an object, interface or union type (September2025
/// 6.4.3): collects the fields of the runtime type from the field's
/// selection sets and executes them on the value.
final class ObjectCompletion {
  /// Completes for [_run].
  ObjectCompletion(this._run) : _abstract = AbstractResolution(_run);

  final ExecutionRun _run;
  final AbstractResolution _abstract;

  /// The object of the selection on [value], an object of [type].
  FutureOr<JsonValue?> complete(
    ObjectType type,
    Object value,
    CompletionSite site,
  ) {
    final node = site.plan.childFor(type);
    if (node.problem case final problem?) {
      _run.reporter.problem(problem, site.path, site.plan.nodes);
      return null;
    }
    return _run.selection.execute(value, node, site.path, site.depth + 1);
  }

  /// The object of the selection on [value], an object of the type that
  /// [type], an interface or union, resolves for it.
  FutureOr<JsonValue?> completeAbstract(
    SchemaType type,
    Object value,
    CompletionSite site,
  ) {
    final runtimeType = _abstract.resolve(type, value, site);
    return runtimeType == null ? null : complete(runtimeType, value, site);
  }
}
