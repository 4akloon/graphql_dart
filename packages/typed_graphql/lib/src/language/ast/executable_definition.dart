import 'child_reader.dart';
import 'definition.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'operation_type.dart';
import 'selection_set.dart';
import 'type_ref.dart';
import 'value.dart';
import 'variable_definition.dart';

/// A definition a server executes: an operation or a fragment (spec §2.2).
sealed class const ExecutableDefinition({super.start, super.end})
    extends Definition {
  /// Creates an executable definition spanning `start` to `end`.
  this;
}

/// An operation, `query Name($v: T) @d { ... }`, or the shorthand
/// `{ ... }` (spec §2.3).
final class OperationDefinition(
  /// Whether it is a query, a mutation or a subscription.
  final OperationType operation,

  /// The selections.
  final SelectionSet selectionSet, {

  /// The description, if any (September2025).
  final StringValue? description,

  /// The name; null for an anonymous operation.
  final Name? name,
  List<VariableDefinition> variableDefinitions = const [],
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends ExecutableDefinition {
  /// Creates an operation.
  this;

  /// The variable definitions, in source order.
  final List<VariableDefinition> variableDefinitions = List.unmodifiable(
    variableDefinitions,
  );

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    ?name,
    ...variableDefinitions,
    ...directives,
    selectionSet,
  ];

  @override
  List<Object?> get scalars => [operation];

  @override
  OperationDefinition rebuildFrom(ChildReader read) => OperationDefinition(
    operation,
    description: read.optional(),
    name: read.optional(),
    variableDefinitions: read.all(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}

/// A fragment, `fragment Name on Type @d { ... }` (spec §2.8).
final class FragmentDefinition(
  /// The fragment name; never `on`.
  final Name name,

  /// The type the fragment applies to.
  final NamedType typeCondition,

  /// The selections.
  final SelectionSet selectionSet, {

  /// The description, if any (September2025).
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends ExecutableDefinition {
  /// Creates a fragment.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    typeCondition,
    ...directives,
    selectionSet,
  ];

  @override
  FragmentDefinition rebuildFrom(ChildReader read) => FragmentDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}
