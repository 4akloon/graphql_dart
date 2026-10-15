import 'named_type_def.dart';

/// The definitions an `ExecutableSchemaBuilder` created, in creation order.
final class DefinitionRegistry() {
  /// Creates an empty registry.
  this;

  final List<NamedTypeDef> _definitions = <NamedTypeDef>[];

  /// A snapshot of the definitions, so one made after a build does not
  /// change a schema already built.
  List<NamedTypeDef> get snapshot => List.unmodifiable(_definitions);

  /// Records [definition] and returns it.
  D add<D extends NamedTypeDef>(D definition) {
    _definitions.add(definition);
    return definition;
  }
}
