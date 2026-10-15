import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'union_type_def.dart';

/// The object types each interface and union can have as a value, in the
/// order the objects were created (the order of the schema).
final class PossibleTypes {
  /// Collects the possible types of every abstract type in [definitions].
  ///
  /// An object counts for each interface it lists and for the interfaces
  /// those list, walked with an explicit stack.
  PossibleTypes(Iterable<NamedTypeDef> definitions) {
    for (final definition in definitions) {
      if (definition is! ObjectTypeDef<Object?>) continue;
      final visited = Set<InterfaceTypeDef<Object?>>.identity();
      final pending = [...definition.interfaces];
      while (pending.isNotEmpty) {
        final next = pending.removeLast();
        if (!visited.add(next)) continue;
        (_implementations[next] ??= []).add(definition);
        pending.addAll(next.interfaces);
      }
    }
  }

  // Lookup only, by identity: never iterated.
  final Map<NamedTypeDef, List<ObjectTypeDef<Object?>>> _implementations =
      Map.identity();

  /// The possible object types of [abstractType]; empty for any other kind.
  List<ObjectTypeDef<Object?>> of(NamedTypeDef abstractType) =>
      switch (abstractType) {
        UnionTypeDef<Object?>(:final members) => members,
        InterfaceTypeDef<Object?>() => _implementations[abstractType] ?? [],
        _ => const [],
      };
}
