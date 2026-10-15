import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../builder/field_def.dart';
import '../builder/field_lane.dart';
import '../coercion/coercion_result.dart';
import '../introspection/entry_fields.dart';
import '../introspection/introspection_policy.dart';
import '../lookahead/field_selection.dart';
import '../plan/field_plan.dart';
import 'completion_site.dart';
import 'execution_run.dart';
import 'field_info.dart';
import 'response_path.dart';

/// Resolves one field (September2025 6.4 "Executing Fields"): answers the
/// meta field `__typename`, or calls the field's pure getter or resolver, then
/// hands the value to the completion. Errors become null and an entry in the
/// log; nothing here throws.
final class FieldExecution {
  /// Executes for [_run].
  FieldExecution(this._run);

  final ExecutionRun _run;

  /// The response value of [plan] on [parent], with the parent's response
  /// path [parentPath], the field's [depth] and its [position] among the
  /// object's fields. Dart `null` when the field failed at a non-null
  /// position, `JsonNull` for a null that stays.
  FutureOr<JsonValue?> execute(
    Object? parent,
    FieldPlan plan,
    ResponsePath parentPath,
    int depth,
    int position,
  ) {
    if (_run.isCancelled) {
      return null;
    }
    final site = CompletionSite(
      plan,
      parentPath.key(plan.responseKey, position),
      depth,
    );
    final field = plan.field;
    if (field == null) {
      return _metaField(plan, site);
    }
    if (_run.options.introspection == IntrospectionPolicy.disabled &&
        const EntryFields().isEntry(plan.fieldName)) {
      return _refused(field.type, site);
    }
    final definition =
        _run.bindings.fields[plan.parentType.name]?[plan.fieldName];
    if (definition == null) {
      _run.reporter.fieldError(
        DiagnosticCode.unexpectedError,
        'Field "${site.fieldLabel}" has no definition to run.',
        site,
      );
      return _run.settle(field.type, null);
    }
    return _resolve(parent, definition, field.type, site);
  }

  /// Opens the source stream of the subscription root field [plan]
  /// (September2025 6.2.3.1 "CreateSourceEventStream") on the root value
  /// [parent]. Null after the problem has been recorded in the run's log:
  /// an argument that cannot be coerced, a source function that threw or
  /// whose future failed. Middleware does not wrap the source (spec 10).
  FutureOr<Stream<Object?>?> openSource(Object? parent, FieldPlan plan) {
    final site = CompletionSite(
      plan,
      ResponsePath.root.key(plan.responseKey, 0),
      1,
    );
    final definition =
        _run.bindings.fields[plan.parentType.name]?[plan.fieldName];
    final lane = definition?.lane;
    final field = plan.field;
    if (definition == null || lane is! SubscribeLane || field == null) {
      _run.reporter.fieldError(
        DiagnosticCode.unexpectedError,
        'Field "${site.fieldLabel}" is not a subscription field.',
        site,
      );
      return null;
    }
    final arguments = _argumentsOf(definition, site);
    if (arguments == null) {
      return null;
    }
    return _callSource(lane, parent, arguments, field.type, site);
  }

  FutureOr<Stream<Object?>?> _callSource(
    SubscribeLane lane,
    Object? parent,
    Arguments arguments,
    TypeRef type,
    CompletionSite site,
  ) {
    try {
      final opened = lane.source(
        parent,
        arguments,
        _run.context,
        _infoOf(type, site),
      );
      return opened is Future<Stream<Object?>>
          ? opened.then<Stream<Object?>?>(
              (stream) => stream,
              onError: (Object error, StackTrace stackTrace) {
                _run.reporter.thrown(error, stackTrace, site);
                return null;
              },
            )
          : opened;
    } on Object catch (error, stackTrace) {
      _run.reporter.thrown(error, stackTrace, site);
      return null;
    }
  }

  // Only `__typename` has no schema field; the planner drops any other
  // name that is not defined.
  FutureOr<JsonValue?> _metaField(FieldPlan plan, CompletionSite site) {
    if (plan.fieldName == '__typename') {
      return JsonString(plan.parentType.name);
    }
    _run.reporter.fieldError(
      DiagnosticCode.unexpectedError,
      'The meta field "${plan.fieldName}" is not available.',
      site,
    );
    return const JsonNull();
  }

  FutureOr<JsonValue?> _refused(TypeRef type, CompletionSite site) {
    _run.reporter.fieldError(
      DiagnosticCode.introspectionNotAllowed,
      'GraphQL introspection has been disabled, but the requested query '
      'contained the field "${site.plan.fieldName}".',
      site,
    );
    return _run.settle(type, null);
  }

  FutureOr<JsonValue?> _resolve(
    Object? parent,
    FieldDef<Object?, Object?> definition,
    TypeRef type,
    CompletionSite site,
  ) {
    if (!_run.limits.admitsDepth(site)) {
      return _run.settle(type, null);
    }
    final arguments = _argumentsOf(definition, site);
    if (arguments == null) {
      return _run.settle(type, null);
    }
    final FutureOr<Object?> raw;
    try {
      raw = _call(parent, definition, arguments, (type, site));
    } on Object catch (error, stackTrace) {
      return _failed(error, stackTrace, type, site);
    }
    if (raw is Future<Object?>) {
      return raw.then<JsonValue?>(
        (value) => _complete(type, value, site),
        onError: (Object error, StackTrace stackTrace) =>
            _failed(error, stackTrace, type, site),
      );
    }
    return _complete(type, raw, site);
  }

  FutureOr<JsonValue?> _complete(
    TypeRef type,
    Object? value,
    CompletionSite site,
  ) {
    try {
      return _run.settle(type, _run.values.complete(type, value, site));
    } on Object catch (error, stackTrace) {
      // User code runs during completion too (isTypeOf, resolveType, codecs).
      return _failed(error, stackTrace, type, site);
    }
  }

  FutureOr<JsonValue?> _failed(
    Object error,
    StackTrace stackTrace,
    TypeRef type,
    CompletionSite site,
  ) {
    _run.reporter.thrown(error, stackTrace, site);
    return _run.settle(type, null);
  }

  // The arguments of a resolver field; null after a coercion problem has
  // been reported. A pure field has none.
  Arguments? _argumentsOf(
    FieldDef<Object?, Object?> definition,
    CompletionSite site,
  ) {
    final lane = definition.lane;
    if (lane is PureLane || lane is DeclaredOnlyLane) {
      return Arguments.empty;
    }
    switch (site.plan.argumentsFor(_run.variables)) {
      case CoercionSuccess(:final value):
        return Arguments(definition.args, value as Map<String, Object?>);
      case CoercionFailure(:final problems):
        for (final problem in problems) {
          _run.reporter.problem(problem, site.path, site.plan.nodes);
        }
        return null;
    }
  }

  // The one place a field's value is asked for.
  FutureOr<Object?> _call(
    Object? parent,
    FieldDef<Object?, Object?> definition,
    Arguments arguments,
    (TypeRef, CompletionSite) where,
  ) => switch (definition.lane) {
    PureLane(:final read) => read(parent),
    ResolverLane(:final resolve) => resolve(
      parent,
      arguments,
      _run.context,
      _infoOf(where.$1, where.$2),
    ),
    // `execute` on a subscription runs it once: the root value is the event.
    SubscribeLane(:final resolve) => resolve(
      parent,
      arguments,
      _run.context,
      _infoOf(where.$1, where.$2),
    ),
    DeclaredOnlyLane() => throw StateError(
      'Field "${where.$2.fieldLabel}" is declared without a resolver.',
    ),
  };

  FieldInfo _infoOf(TypeRef type, CompletionSite site) {
    final plan = site.plan;
    return FieldInfo(
      fieldName: plan.fieldName,
      parentType: plan.parentType,
      returnType: type,
      path: site.path,
      fieldNodes: plan.nodes,
      operation: _run.plan.operation,
      variables: _run.rawVariables,
      schema: _run.schema,
      rootValue: _run.options.rootValue,
      cancelSignal: _run.cancellation?.signal,
      selectionReader: () => FieldSelection.under(
        [plan],
        _run.variables,
        _run.bindings.fields,
      ),
    );
  }
}
