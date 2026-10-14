import 'child_reader.dart';
import 'node.dart';
import 'type_system_extension.dart';

/// Rebuilds a [TypeSystemExtension] for [Node.withChildren]; apart from
/// the node classes so their library stays within the size limit.
final class const TypeSystemExtensionRebuilder() {
  /// Creates the rebuilder.
  this;

  /// An extension of [node]'s kind, with its positions and the children
  /// [read] returns.
  TypeSystemExtension rebuild(TypeSystemExtension node, ChildReader read) =>
      switch (node) {
        SchemaExtension() => SchemaExtension(
          directives: read.all(),
          operationTypes: read.all(),
          start: node.start,
          end: node.end,
        ),
        DirectiveExtension() => DirectiveExtension(
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ScalarTypeExtension() => ScalarTypeExtension(
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ObjectTypeExtension() => _object(node, read),
        InterfaceTypeExtension() => _interface(node, read),
        UnionTypeExtension() => _union(node, read),
        EnumTypeExtension() => _enum(node, read),
        InputObjectTypeExtension() => _inputObject(node, read),
      };

  ObjectTypeExtension _object(ObjectTypeExtension node, ChildReader read) =>
      ObjectTypeExtension(
        read.one(),
        interfaces: read.all(),
        directives: read.all(),
        fields: read.all(),
        start: node.start,
        end: node.end,
      );

  InterfaceTypeExtension _interface(
    InterfaceTypeExtension node,
    ChildReader read,
  ) => InterfaceTypeExtension(
    read.one(),
    interfaces: read.all(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );

  UnionTypeExtension _union(UnionTypeExtension node, ChildReader read) =>
      UnionTypeExtension(
        read.one(),
        directives: read.all(),
        types: read.all(),
        start: node.start,
        end: node.end,
      );

  EnumTypeExtension _enum(EnumTypeExtension node, ChildReader read) =>
      EnumTypeExtension(
        read.one(),
        directives: read.all(),
        values: read.all(),
        start: node.start,
        end: node.end,
      );

  InputObjectTypeExtension _inputObject(
    InputObjectTypeExtension node,
    ChildReader read,
  ) => InputObjectTypeExtension(
    read.one(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );
}
