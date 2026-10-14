import '../model/named_type_reference.dart';
import '../model/schema_type.dart';

/// The object and interface types that declare each interface, in
/// declaration order: graphql-js's `getImplementations`, built once.
///
/// It reads only the `implements` lists, so a transitive interface counts
/// only where it is declared, as schema validation requires (spec
/// §3.7.2).
final class ImplementationIndex(List<SchemaType> types) {
  /// Indexes [types].
  this;

  // Only for lookups, never iterated.
  final Map<String, List<SchemaType>> _byInterface = _index(types);

  /// The types that declare the interface named [interfaceName].
  List<SchemaType> of(String interfaceName) =>
      _byInterface[interfaceName] ?? const [];

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
        if (!implementers.contains(type)) {
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
