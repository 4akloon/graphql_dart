import 'package:typed_graphql/typed_graphql.dart';

import '../plan/field_plan.dart';

/// What decides that two plans of a response key are one selected field:
/// the key, the field's name and its arguments as written.
///
/// Object types that cannot overlap may give one alias to different fields
/// (spec 5.3.2, `FieldsInSetCanMerge` only compares fields of overlapping
/// types), so the key alone would merge fields that are not the same.
final class MergeKey {
  /// Creates the writer.
  const MergeKey();

  /// The text of [plan]'s merge key; arguments sorted by their text.
  String of(FieldPlan plan) {
    final arguments = plan.nodes.first.arguments;
    if (arguments.isEmpty) {
      return '${plan.responseKey}\u0000${plan.fieldName}';
    }
    final printed = [
      for (final argument in arguments) const Printer().print(argument),
    ]..sort();
    return '${plan.responseKey}\u0000${plan.fieldName}\u0000'
        '${printed.join(',')}';
  }
}
