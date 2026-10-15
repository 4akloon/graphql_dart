import 'package:typed_graphql/typed_graphql.dart';

import '../builder/object_type_def.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Finds the object type of a value of an interface or union (September2025
/// 6.4.3 "ResolveAbstractType"): the abstract type's `resolveType`, else the
/// first possible type that accepts the value.
final class AbstractResolution {
  /// Resolves for [_run].
  AbstractResolution(this._run);

  final ExecutionRun _run;

  /// The object type of [value] for the abstract [type], or null after
  /// reporting why there is none.
  ObjectType? resolve(SchemaType type, Object value, CompletionSite site) {
    final binding = _run.bindings.abstractTypes[type.name];
    if (binding == null) {
      throw StateError('"${type.name}" has no abstract type binding.');
    }
    final ObjectTypeDef<Object?>? chosen;
    try {
      chosen = _choose(binding.resolveType, binding.possibleTypes, value);
    } on Object catch (error, stackTrace) {
      _run.reporter.thrown(error, stackTrace, site);
      return null;
    }
    if (chosen == null) {
      _run.reporter.fieldError(
        DiagnosticCode.unresolvedAbstractType,
        'Abstract type "${type.name}" must resolve to an Object type at '
        'runtime for field "${site.fieldLabel}". Either the "${type.name}" '
        'type should provide a "resolveType" function or each possible type '
        'should provide an "isTypeOf" function.',
        site,
      );
      return null;
    }
    if (!binding.possibleTypes.contains(chosen)) {
      _run.reporter.fieldError(
        DiagnosticCode.impossibleRuntimeType,
        'Runtime Object type "${chosen.name}" is not a possible type for '
        '"${type.name}".',
        site,
      );
      return null;
    }
    return switch (_run.schema.schema.typeNamed(chosen.name)) {
      final ObjectType objectType => objectType,
      _ => throw StateError('"${chosen.name}" is not an object type.'),
    };
  }

  ObjectTypeDef<Object?>? _choose(
    ObjectTypeDef<Object?> Function(Object? value)? explicit,
    List<ObjectTypeDef<Object?>> possible,
    Object value,
  ) {
    if (explicit != null) {
      return explicit(value);
    }
    for (final candidate in possible) {
      if (candidate.accepts(value)) {
        return candidate;
      }
    }
    return null;
  }
}
