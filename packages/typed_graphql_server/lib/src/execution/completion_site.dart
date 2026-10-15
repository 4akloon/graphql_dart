import '../plan/field_plan.dart';
import 'response_path.dart';

/// Where a value is completed: the field it belongs to, its place in the
/// response and how deep that place is. Immutable.
final class CompletionSite {
  /// A place of the field [plan] at [path], [depth] levels down.
  const CompletionSite(this.plan, this.path, this.depth);

  /// The field being answered.
  final FieldPlan plan;

  /// The response path of the value.
  final ResponsePath path;

  /// How many fields and list levels lie between the root and the value.
  final int depth;

  /// The place of the list item at [position].
  CompletionSite itemAt(int position) =>
      CompletionSite(plan, path.index(position), depth + 1);

  /// The name of the field with its object type, as messages write it.
  String get fieldLabel => '${plan.parentType.name}.${plan.fieldName}';
}
