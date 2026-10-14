import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// An argument or input field definition, `"desc" name: Type = default
/// @d` (spec §3.6.1, §3.10).
final class InputValueDefinition(
  /// The name.
  final Name name,

  /// The input type.
  final TypeRef type, {

  /// The description, if any.
  final StringValue? description,

  /// The default value, if any; a constant.
  final Value? defaultValue,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates an input value definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    type,
    ?defaultValue,
    ...directives,
  ];

  @override
  InputValueDefinition rebuildFrom(ChildReader read) => InputValueDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    defaultValue: read.optional(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
