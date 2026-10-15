import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'execution_run.dart';

/// Completes a resolved value by its type (September2025 6.4.3 "Value
/// Completion"). The result is a `JsonValue`, or Dart `null` when the value
/// failed and the failure propagates to the position that can hold a null
/// (6.4.4); `JsonNull` is a real null.
final class ValueCompletion {
  /// Completes for [_run].
  ValueCompletion(this._run);

  final ExecutionRun _run;

  /// The response value of [value] at a place of type [type].
  FutureOr<JsonValue?> complete(
    TypeRef type,
    Object? value,
    CompletionSite site,
  ) {
    if (!_run.limits.admits(site)) {
      return null;
    }
    final isNonNull = type is NonNullType;
    final inner = type is NonNullType ? type.type : type;
    if (value == null) {
      return isNonNull ? _nullViolation(site) : const JsonNull();
    }
    final completed = switch (inner) {
      ListType() => _run.lists.complete(inner, value, site),
      NamedType(:final name) => _named(name.value, value, site),
      NonNullType() => throw StateError('A non-null type wraps another.'),
    };
    return isNonNull ? _guardNull(completed, site) : completed;
  }

  FutureOr<JsonValue?> _named(
    String name,
    Object value,
    CompletionSite site,
  ) => switch (_run.schema.schema.typeNamed(name)) {
    final ScalarType type => _run.leaves.complete(type, value, site),
    final EnumType type => _run.leaves.complete(type, value, site),
    final ObjectType type => _run.objects.complete(type, value, site),
    final InterfaceType type => _run.objects.completeAbstract(
      type,
      value,
      site,
    ),
    final UnionType type => _run.objects.completeAbstract(type, value, site),
    _ => throw StateError('"$name" is not an output type of the schema.'),
  };

  // A non-null position refuses the null a codec may encode to, as it
  // refuses the null a resolver returns.
  FutureOr<JsonValue?> _guardNull(
    FutureOr<JsonValue?> completed,
    CompletionSite site,
  ) {
    if (completed is Future<JsonValue?>) {
      return completed.then((value) => _guardSettled(value, site));
    }
    return _guardSettled(completed, site);
  }

  JsonValue? _guardSettled(JsonValue? value, CompletionSite site) =>
      value is JsonNull ? _nullViolation(site) : value;

  JsonValue? _nullViolation(CompletionSite site) {
    _run.reporter.fieldError(
      DiagnosticCode.nullNonNullField,
      'Cannot return null for non-nullable field ${site.fieldLabel}.',
      site,
    );
    return null;
  }
}
