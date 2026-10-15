import 'data_class_role.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';

/// A class to generate, which refers to other classes by name.
sealed class PlannedClass {
  /// Creates a plan.
  const PlannedClass(this.name);

  /// The class name.
  final String name;
}

/// A class with the fields of a selection.
final class DataClassPlan extends PlannedClass {
  /// Creates a data class plan.
  const DataClassPlan({
    required String name,
    required this.role,
    required this.typeName,
    required this.fields,
    this.holderName,
    this.ownerName,
    this.ownerMember,
  }) : super(name);

  /// What the class is the shape of.
  final DataClassRole role;

  /// The GraphQL type the selection is on.
  final String typeName;

  /// The fields, `__typename` first.
  final List<PlannedField> fields;

  /// The fragment holder class, when the selection spreads fragments.
  final String? holderName;

  /// For a nested class, the class that has the field.
  final String? ownerName;

  /// For a nested class, the member of the owner it is the class of.
  final String? ownerMember;
}

/// The class that holds the fragments spread on [ownerName].
final class FragmentHolderPlan extends PlannedClass {
  /// Creates a holder plan.
  const FragmentHolderPlan({
    required String name,
    required this.ownerName,
    required this.fragments,
  }) : super(name);

  /// The class whose selection spreads the fragments.
  final String ownerName;

  /// The fragments, in first-occurrence order.
  final List<PlannedFragment> fragments;
}
