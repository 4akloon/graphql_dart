import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'type_system_definition.dart';
import 'value.dart';

/// Rebuilds a [TypeSystemDefinition] for [Node.withChildren]; apart from
/// the node classes so their library stays within the size limit.
final class const TypeSystemDefinitionRebuilder() {
  /// Creates the rebuilder.
  this;

  /// A definition of [node]'s kind, with its scalar fields and positions
  /// and the children [read] returns.
  TypeSystemDefinition rebuild(TypeSystemDefinition node, ChildReader read) =>
      switch (node) {
        SchemaDefinition() => SchemaDefinition(
          description: read.optional(),
          directives: read.all(),
          operationTypes: read.all(),
          start: node.start,
          end: node.end,
        ),
        DirectiveDefinition() => _directive(node, read),
        ScalarTypeDefinition() => ScalarTypeDefinition(
          description: read.optional(),
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ObjectTypeDefinition() => _object(node, read),
        InterfaceTypeDefinition() => _interface(node, read),
        UnionTypeDefinition() => _union(node, read),
        EnumTypeDefinition() => _enum(node, read),
        InputObjectTypeDefinition() => _inputObject(node, read),
      };

  DirectiveDefinition _directive(DirectiveDefinition node, ChildReader read) {
    final description = read.optional<StringValue>();
    final name = read.one<Name>();
    // Without arguments or directives, a removed name leaves the first
    // location where the name is read.
    if (node.locations.any((location) => identical(location, name))) {
      throw StateError(
        'Removing a directive name is ambiguous: a location would become '
        'the name. Rewrite the DirectiveDefinition instead.',
      );
    }
    return DirectiveDefinition(
      description: description,
      name,
      arguments: read.all(),
      directives: read.all(),
      isRepeatable: node.isRepeatable,
      locations: read.all(),
      start: node.start,
      end: node.end,
    );
  }

  ObjectTypeDefinition _object(ObjectTypeDefinition node, ChildReader read) =>
      ObjectTypeDefinition(
        description: read.optional(),
        read.one(),
        interfaces: read.all(),
        directives: read.all(),
        fields: read.all(),
        start: node.start,
        end: node.end,
      );

  InterfaceTypeDefinition _interface(
    InterfaceTypeDefinition node,
    ChildReader read,
  ) => InterfaceTypeDefinition(
    description: read.optional(),
    read.one(),
    interfaces: read.all(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );

  UnionTypeDefinition _union(UnionTypeDefinition node, ChildReader read) =>
      UnionTypeDefinition(
        description: read.optional(),
        read.one(),
        directives: read.all(),
        types: read.all(),
        start: node.start,
        end: node.end,
      );

  EnumTypeDefinition _enum(EnumTypeDefinition node, ChildReader read) =>
      EnumTypeDefinition(
        description: read.optional(),
        read.one(),
        directives: read.all(),
        values: read.all(),
        start: node.start,
        end: node.end,
      );

  InputObjectTypeDefinition _inputObject(
    InputObjectTypeDefinition node,
    ChildReader read,
  ) => InputObjectTypeDefinition(
    description: read.optional(),
    read.one(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );
}
