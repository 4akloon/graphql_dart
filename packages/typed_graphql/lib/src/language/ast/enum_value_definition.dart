import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// A value of an enum type, `"desc" NAME @d` (spec §3.9).
final class EnumValueDefinition(
  /// The value's name; never `true`, `false` or `null`.
  final Name name, {

  /// The description, if any.
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates an enum value definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [?description, name, ...directives];

  @override
  EnumValueDefinition rebuildFrom(ChildReader read) => EnumValueDefinition(
    description: read.optional(),
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
