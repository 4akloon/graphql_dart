import 'data_class_role.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';
import 'variant_reference.dart';

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
    this.baseName,
    this.variantTypeName,
    this.holderOverridesBase = false,
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

  /// For a variant, the sealed base it implements.
  final String? baseName;

  /// For a [DataClassRole.variant], the concrete type it is the class of;
  /// null for the other roles.
  final String? variantTypeName;

  /// Whether [holderName] is the base's shared holder, which `fragments`
  /// overrides.
  final bool holderOverridesBase;
}

/// The sealed base of a selection on an abstract type that tells types
/// apart: a class per reached type, and one for any other.
final class PolymorphicBasePlan extends PlannedClass {
  /// Creates a base plan.
  const PolymorphicBasePlan({
    required String name,
    required this.role,
    required this.typeName,
    required this.sharedFields,
    required this.variants,
    required this.unknownName,
    this.holderName,
    this.ownerName,
    this.ownerMember,
  }) : super(name);

  /// What the class is the shape of: a fragment or a nested class.
  final DataClassRole role;

  /// The abstract GraphQL type the selection is on.
  final String typeName;

  /// The fields every variant has with the same selection; the base
  /// declares them.
  final List<PlannedField> sharedFields;

  /// The shared fragment holder class, when every variant has the base's
  /// fragments.
  final String? holderName;

  /// The classes of the reached types, in possible-types order.
  final List<VariantReference> variants;

  /// The class for every other `__typename`.
  final String unknownName;

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
