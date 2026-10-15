import 'package:typed_graphql/typed_graphql.dart';

import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import '../plan/planned_field.dart';

/// Writes the doc comment sentence of a planned data class.
///
/// {@category codegen}
final class ClassDocumentation {
  /// Creates the writer; [classes] are the plan the classes belong to, in
  /// which an owner is looked up by name.
  const ClassDocumentation(this.classes);

  /// The planned classes of one fragment or operation.
  final List<PlannedClass> classes;

  /// The doc of [plan].
  ///
  /// [fragmentName] is the GraphQL name of the fragment a
  /// [DataClassRole.fragment] class is the shape of. A role this stage does
  /// not generate, or a nested class whose owner is not in [classes], is a
  /// [StateError].
  String of(DataClassPlan plan, {String? fragmentName}) => switch (plan.role) {
    DataClassRole.fragment =>
      'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`.',
    DataClassRole.nested => _nested(plan),
    _ => throw StateError('${plan.name} is a ${plan.role.name} class.'),
  };

  String _nested(DataClassPlan plan) {
    final String? ownerName = plan.ownerName;
    final String? member = plan.ownerMember;
    final PlannedField? field = ownerName == null || member == null
        ? null
        : _fieldOf(ownerName, member);
    if (field == null) {
      throw StateError('The owner field of ${plan.name} is not planned.');
    }
    final String subject = '`${field.responseName}` of [$ownerName]';
    return _isList(field.type)
        ? 'The items of the field $subject.'
        : 'The field $subject.';
  }

  PlannedField? _fieldOf(String ownerName, String member) {
    for (final PlannedClass candidate in classes) {
      if (candidate.name != ownerName) continue;
      final List<PlannedField> fields = switch (candidate) {
        DataClassPlan(:final fields) => fields,
        PolymorphicBasePlan(:final sharedFields) => sharedFields,
        FragmentHolderPlan() => const [],
      };
      for (final PlannedField field in fields) {
        if (field.memberName == member) return field;
      }
    }
    return null;
  }

  bool _isList(TypeRef type) => switch (type) {
    NonNullType(type: final inner) => _isList(inner),
    ListType() => true,
    NamedType() => false,
  };
}
