import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'union_type_def.dart';

/// The object types each interface and union can have as a value, in the
/// order the objects were created (the order of the schema).
final class PossibleTypes {
  /// Collects the possible types of every abstract type in [definitions].
  ///
  /// An object counts for each interface it lists itself, as in graphql-js
  /// and the core `Schema`; an object must list the interfaces of its
  /// interfaces too, and the core validator reports one that does not.
  PossibleTypes(Iterable<NamedTypeDef> definitions) {
    for (final definition in definitions) {
      if (definition is! ObjectTypeDef<Object?>) continue;
      final listed = Set<InterfaceTypeDef<Object?>>.identity()
        ..addAll(definition.interfaces);
      for (final interface in listed) {
        (_implementations[interface] ??= []).add(definition);
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
