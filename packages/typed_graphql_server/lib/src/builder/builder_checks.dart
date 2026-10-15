import 'package:typed_graphql/typed_graphql.dart';

import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'union_type_def.dart';

/// The checks only the builder can make, because they are about Dart types:
/// `GQL300` (implementations) and `GQL301` (type resolution). The core
/// validator runs after them.
final class BuilderChecks {
  /// Creates the checks; they add problems to [problems].
  BuilderChecks(this.problems);

  /// The diagnostics found so far; the checks add to them.
  final List<Diagnostic> problems;

  /// Runs both checks over [definitions].
  void check(List<NamedTypeDef> definitions, PossibleTypes possibleTypes) {
    for (final definition in definitions) {
      switch (definition) {
        case ObjectTypeDef<Object?>():
          _checkInterfaces(
            definition.name,
            definition.dartTypeName,
            definition.interfaces,
            definition.isDartSubtypeOfInterface,
          );
        case InterfaceTypeDef<Object?>():
          _checkInterfaces(
            definition.name,
            definition.dartTypeName,
            definition.interfaces,
            definition.isDartSubtypeOf,
          );
        // `NamedTypeDef` is not sealed, so the switch needs a default.
        default:
      }
    }
    _checkTypeResolution(definitions, possibleTypes);
  }

  void _checkInterfaces(
    String name,
    String dartTypeName,
    List<InterfaceTypeDef<Object?>> interfaces,
    bool Function(InterfaceTypeDef<Object?> interface) isSubtype,
  ) {
    for (final interface in interfaces) {
      if (isSubtype(interface)) continue;
      problems.add(
        Diagnostic(
          .incompatibleImplementation,
          .error,
          'Type "$name" (Dart type $dartTypeName) cannot implement '
          'interface "${interface.name}": $dartTypeName is not a subtype of '
          '${interface.dartTypeName}.',
        ),
      );
    }
  }

  void _checkTypeResolution(
    List<NamedTypeDef> definitions,
    PossibleTypes possibleTypes,
  ) {
    for (final definition in definitions) {
      final hasResolveType = switch (definition) {
        InterfaceTypeDef<Object?>(:final hasResolveType) => hasResolveType,
        UnionTypeDef<Object?>(:final hasResolveType) => hasResolveType,
        _ => true,
      };
      if (hasResolveType) continue;
      _checkPairs(definition.name, possibleTypes.of(definition));
    }
  }

  // Reports the first ambiguous pair only: a pair per overlap would be
  // quadratic output for a large interface.
  void _checkPairs(String abstractName, List<ObjectTypeDef<Object?>> types) {
    for (var i = 0; i < types.length; i++) {
      for (var j = i + 1; j < types.length; j++) {
        if (!_isAmbiguous(types[i], types[j])) continue;
        problems.add(_ambiguity(abstractName, types[i], types[j]));
        return;
      }
    }
  }

  // Spec 3.7: the default decision is `value is P` in order, so it guesses
  // when one Dart type holds the other's values, unless both types decide
  // with an explicit isTypeOf.
  bool _isAmbiguous(ObjectTypeDef<Object?> a, ObjectTypeDef<Object?> b) {
    final hasBothTests =
        a.options.isTypeOf != null && b.options.isTypeOf != null;
    return !hasBothTests && (a.isDartSubtypeOf(b) || b.isDartSubtypeOf(a));
  }

  Diagnostic _ambiguity(
    String abstractName,
    ObjectTypeDef<Object?> a,
    ObjectTypeDef<Object?> b,
  ) => Diagnostic(
    .ambiguousTypeResolution,
    .error,
    'The possible types "${a.name}" (Dart type ${a.dartTypeName}) and '
    '"${b.name}" (Dart type ${b.dartTypeName}) of "$abstractName" have '
    'overlapping Dart types, so a value cannot be matched to one of them: '
    'give "$abstractName" a resolveType, or give both types an isTypeOf.',
  );
}
