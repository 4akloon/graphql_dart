import '../model/named_type_reference.dart';
import '../model/schema_type.dart';

/// The object and interface types that declare each interface, and the
/// object types that are possible for each abstract type, in declaration
/// order: graphql-js's `getImplementations` and `getPossibleTypes`, each
/// answer built once and answered with a set lookup.
///
/// It reads only the `implements` lists, so a transitive interface counts
/// only where it is declared, as schema validation requires (spec
/// §3.7.2). [typeNamed] resolves the members of a union.
final class ImplementationIndex(
  List<SchemaType> types,
  final SchemaType? Function(String name) typeNamed,
) {
  /// Indexes [types].
  this;

  // Only for lookups, never iterated.
  final Map<String, List<SchemaType>> _byInterface = _index(types);

  // Filled on the first question about a type; a type compares by
  // identity, so these are identity maps and sets.
  final Map<SchemaType, List<ObjectType>> _possibleLists = {};
  final Map<SchemaType, Set<ObjectType>> _possibleSets = {};
  final Map<String, Set<SchemaType>> _implementerSets = {};

  /// The types that declare the interface named [interfaceName].
  List<SchemaType> of(String interfaceName) =>
      _byInterface[interfaceName] ?? const [];

  /// Whether the type [candidate] declares the interface named
  /// [interfaceName].
  bool declares(String interfaceName, SchemaType candidate) {
    final implementers = _byInterface[interfaceName];
    if (implementers == null) {
      return false;
    }
    return (_implementerSets[interfaceName] ??= implementers.toSet()).contains(
      candidate,
    );
  }

  /// The object types possible for [type], in declaration order,
  /// unmodifiable: the object itself, the members of a union that are
  /// objects, or the objects that declare an interface.
  List<ObjectType> possibleOf(SchemaType type) => switch (type) {
    ObjectType() => List.unmodifiable([type]),
    InterfaceType() || UnionType() => _possibleLists[type] ??= _collect(type),
    ScalarType() || EnumType() || InputObjectType() => const [],
  };

  /// Whether [object] is one of the object types possible for [type].
  bool isPossible(SchemaType type, ObjectType object) => switch (type) {
    ObjectType() => identical(type, object),
    InterfaceType() || UnionType() => (_possibleSets[type] ??= possibleOf(
      type,
    ).toSet()).contains(object),
    ScalarType() || EnumType() || InputObjectType() => false,
  };

  List<ObjectType> _collect(SchemaType type) {
    final collected = <ObjectType>{};
    switch (type) {
      case InterfaceType(:final name):
        collected.addAll(of(name).whereType<ObjectType>());
      case UnionType(:final memberTypes):
        for (final member in memberTypes) {
          if (typeNamed(member.name) case final ObjectType object) {
            collected.add(object);
          }
        }
      case _:
    }
    return List.unmodifiable(collected);
  }

  static Map<String, List<SchemaType>> _index(List<SchemaType> types) {
    final index = <String, List<SchemaType>>{};
    for (final type in types) {
      final interfaces = switch (type) {
        ObjectType(:final interfaces) ||
        InterfaceType(:final interfaces) => interfaces,
        _ => const <NamedTypeReference>[],
      };
      for (final reference in interfaces) {
        final implementers = index.putIfAbsent(reference.name, () => []);
        // Types are indexed one at a time, so a repeat is always the last.
        if (implementers.isEmpty || !identical(implementers.last, type)) {
          implementers.add(type);
        }
      }
    }
    return {
      for (final MapEntry(:key, :value) in index.entries)
        key: List.unmodifiable(value),
    };
  }
}
