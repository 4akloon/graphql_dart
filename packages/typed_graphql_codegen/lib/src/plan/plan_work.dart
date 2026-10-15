import 'package:typed_graphql/typed_graphql.dart';

import 'data_class_role.dart';
import 'planned_class.dart';
import 'selection_source.dart';
import 'variant_context.dart';

/// An item of the planner's work stack.
sealed class PlanWork {
  /// Creates an item.
  const PlanWork();
}

/// A class plan that is already complete.
final class ReadyWork extends PlanWork {
  /// Wraps [plan].
  const ReadyWork(this.plan);

  /// The plan to emit when the item is popped.
  final PlannedClass plan;
}

/// A selection to plan as a class.
final class ClassWork extends PlanWork {
  /// Creates the work for the class [name].
  const ClassWork(
    this.name,
    this.parent,
    this.sources,
    this.role, {
    this.ownerName,
    this.ownerMember,
    this.variant,
  });

  /// The class name.
  final String name;

  /// The type the selection is on.
  final SchemaType parent;

  /// The selection sets, in document order.
  final List<SelectionSource> sources;

  /// What the class is the shape of.
  final DataClassRole role;

  /// For a nested class, the class that has the field.
  final String? ownerName;

  /// For a nested class, the member of the owner it is the class of.
  final String? ownerMember;

  /// What a variant takes from its sealed base; null for any other class.
  final VariantContext? variant;
}
