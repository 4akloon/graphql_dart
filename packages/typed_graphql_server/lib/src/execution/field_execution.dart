import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../builder/field_def.dart';
import '../builder/field_lane.dart';
import '../coercion/coercion_result.dart';
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
    final site = CompletionSite(
      plan,
      parentPath.key(plan.responseKey, position),
      depth,
    );
    final field = plan.field;
    if (field == null) {
      return _metaField(plan, site);
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

  FutureOr<JsonValue?> _metaField(FieldPlan plan, CompletionSite site) {
    if (plan.fieldName == '__typename') {
      return JsonString(plan.parentType.name);
    }
    _run.reporter.fieldError(
      DiagnosticCode.unexpectedError,
      'The introspection field "${plan.fieldName}" is not available.',
      site,
    );
    return _run.settle(_metaFieldType(plan.fieldName), null);
  }

  // `__schema` is non-null, `__type` nullable (September2025 4.1.4).
  TypeRef _metaFieldType(String fieldName) => fieldName == '__schema'
      ? const NonNullType(NamedType(Name('__Schema')))
      : const NamedType(Name('__Type'));

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
    if (definition.lane is! ResolverLane) {
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
    );
  }
}
