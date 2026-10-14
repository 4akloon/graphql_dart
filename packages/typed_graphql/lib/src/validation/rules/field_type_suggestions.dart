import '../../diagnostics/suggestions.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'engine_ordered_sort.dart';

/// The types to condition on when an abstract type lacks a field
/// (graphql-js's `getSuggestedTypeNames`): the possible types that define
/// it and the interfaces of those, the most used first.
final class FieldTypeSuggestions(final Schema schema) {
  /// Creates the suggestions over [schema].
  this;

  /// The names of the object and interface types that define [fieldName]
  /// among the possible types of [parent]; empty unless [parent] is
  /// abstract.
  List<String> namesFor(SchemaType parent, String fieldName) {
    if (!parent.isAbstractType) {
      return const [];
    }
    final suggested = <SchemaType>{};
    final usageCount = <String, int>{};
    for (final possible in schema.possibleTypes(parent)) {
      if (possible.fieldNamed(fieldName) == null) {
        continue;
      }
      suggested.add(possible);
      usageCount[possible.name] = 1;
      for (final reference in possible.interfaces) {
        if (schema.typeNamed(reference.name) case final InterfaceType type
            when type.fieldNamed(fieldName) != null) {
          suggested.add(type);
          usageCount[type.name] = (usageCount[type.name] ?? 0) + 1;
        }
      }
    }
    final sorted = EngineOrderedSort<SchemaType>(
      (a, b) => _compare(a, b, usageCount),
    ).sorted(suggested);
    return [for (final type in sorted) type.name];
  }

  // Most used first, then super types before their subtypes, then by name.
  int _compare(SchemaType a, SchemaType b, Map<String, int> usageCount) {
    final usageDifference =
        (usageCount[b.name] ?? 0) - (usageCount[a.name] ?? 0);
    if (usageDifference != 0) {
      return usageDifference;
    }
    if (a is InterfaceType && schema.isSubType(a, b)) {
      return -1;
    }
    if (b is InterfaceType && schema.isSubType(b, a)) {
      return 1;
    }
    return const Suggestions().naturalCompare(a.name, b.name);
  }
}
