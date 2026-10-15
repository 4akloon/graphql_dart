import 'package:typed_graphql/typed_graphql.dart';

import '../emit/input_field.dart';
import '../plan/class_names.dart';
import '../plan/planned_class.dart';
import '../plan/planned_field.dart';
import '../plan/shape_planner.dart';
import 'client_project.dart';
import 'generated_names.dart';

/// Registers every class the operations and fragments of a project declare
/// in [GeneratedNames], with the members of each (spec §7 "Names").
final class DocumentNameChecker {
  /// Creates the checker of [project]'s documents, planning with [planner].
  const DocumentNameChecker(this.project, this.planner, this.names);

  /// The project whose documents are checked.
  final ClientProject project;

  /// The class planner.
  final ShapePlanner planner;

  /// The registry the names are recorded in.
  final GeneratedNames names;

  static const ClassNames _classNames = ClassNames();

  /// Registers the classes of every operation and fragment.
  void check() {
    for (final definition in project.document.document.definitions) {
      switch (definition) {
        case OperationDefinition():
          _operation(definition);
        case FragmentDefinition():
          _plans(
            "the fragment '${definition.name.value}'",
            definition.name,
            planner.planFragment(definition),
          );
        default:
      }
    }
  }

  void _operation(OperationDefinition operation) {
    final String name = operation.name?.value ?? '';
    final String declarer = "the operation '$name'";
    final SourceSpan? span = _spanOf(operation.name ?? operation);
    final classes = planner.planOperation(operation);
    if (classes.isEmpty) return;
    names.register(
      _classNames.operation(name, operation.operation),
      declarer,
      span,
    );
    if (operation.variableDefinitions.isNotEmpty) {
      final String variables = _classNames.variables(name);
      names.register(variables, declarer, span);
      names.registerMembers("'$variables'", [
        for (final definition in operation.variableDefinitions)
          (
            InputField.dartNameOf(definition.variable.name.value),
            "the variable '${definition.variable.name.value}'",
            _spanOf(definition),
          ),
      ]);
    }
    _plans(declarer, operation.name ?? operation, classes);
  }

  void _plans(String declarer, Node definitionName, List<PlannedClass> plans) {
    final SourceSpan? definitionSpan = _spanOf(definitionName);
    final spans = _fieldClassSpans(plans);
    for (final plan in plans) {
      names.register(
        plan.name,
        declarer,
        spans[plan.name] ??
            (switch (plan) {
              DataClassPlan(:final baseName?) => spans[baseName],
              FragmentHolderPlan(:final ownerName) => spans[ownerName],
              _ => null,
            }) ??
            definitionSpan,
      );
      names.registerMembers("'${plan.name}'", _membersOf(plan));
    }
  }

  // The span of the first field node each nested class is the class of.
  Map<String, SourceSpan?> _fieldClassSpans(List<PlannedClass> plans) {
    final spans = <String, SourceSpan?>{};
    for (final plan in plans) {
      final fields = switch (plan) {
        DataClassPlan(:final fields) => fields,
        PolymorphicBasePlan(:final sharedFields) => sharedFields,
        FragmentHolderPlan() => const <PlannedField>[],
      };
      for (final field in fields) {
        final className = field.className;
        final node = field.node;
        if (className != null && node != null) {
          spans.putIfAbsent(className, () => _spanOf(node));
        }
      }
    }
    return spans;
  }

  List<(String, String, SourceSpan?)> _membersOf(PlannedClass plan) =>
      switch (plan) {
        DataClassPlan(:final fields) => _fieldMembers(fields),
        PolymorphicBasePlan(:final sharedFields) => _fieldMembers(sharedFields),
        FragmentHolderPlan(:final fragments) => [
          for (final fragment in fragments)
            (
              fragment.memberName,
              "the fragment '${fragment.fragmentName}'",
              fragment.spread == null ? null : _spanOf(fragment.spread),
            ),
        ],
      };

  List<(String, String, SourceSpan?)> _fieldMembers(
    List<PlannedField> fields,
  ) => [
    for (final field in fields)
      (
        field.memberName,
        "the field '${field.responseName}'",
        field.node == null ? null : _spanOf(field.node),
      ),
  ];

  SourceSpan? _spanOf(Node? node) {
    if (node == null) return null;
    final map = project.documents.sourceMap;
    return map.translate(SourceSpan(map.source, node.start, node.end));
  }
}
