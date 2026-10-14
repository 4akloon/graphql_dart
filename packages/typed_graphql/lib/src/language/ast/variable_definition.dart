import 'child_reader.dart';
import 'directive.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// A variable definition of an operation, `$name: Type = default
/// @directives` (spec §2.10).
final class VariableDefinition(
  /// The variable.
  final Variable variable,

  /// The variable's type.
  final TypeRef type, {

  /// The description, if any (September2025).
  final StringValue? description,

  /// The default value, if any; a constant.
  final Value? defaultValue,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a variable definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    variable,
    type,
    ?defaultValue,
    ...directives,
  ];

  @override
  VariableDefinition rebuildFrom(ChildReader read) => VariableDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    defaultValue: read.optional(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
