import 'child_reader.dart';
import 'directive.dart';
import 'input_value_definition.dart';
import 'name.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// A field of an object or interface type, `"desc" name(args): Type @d`
/// (spec §3.6).
///
/// {@category language}
final class FieldDefinition(
  /// The field name.
  final Name name,

  /// The output type.
  final TypeRef type, {

  /// The description, if any.
  final StringValue? description,
  List<InputValueDefinition> arguments = const [],
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a field definition.
  this;

  /// The argument definitions, in source order.
  final List<InputValueDefinition> arguments = List.unmodifiable(arguments);

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...arguments,
    type,
    ...directives,
  ];

  @override
  FieldDefinition rebuildFrom(ChildReader read) => FieldDefinition(
    description: read.optional(),
    read.one(),
    arguments: read.all(),
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
