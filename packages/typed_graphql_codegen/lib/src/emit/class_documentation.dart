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
  /// [DataClassRole.fragment] class is the shape of. An operation's data
  /// class is not documented here, and a nested class whose owner is not in
  /// [classes] is a [StateError].
  String of(DataClassPlan plan, {String? fragmentName}) =>
      _wrapped(_sentence(plan, fragmentName));

  String _sentence(DataClassPlan plan, String? fragmentName) =>
      switch (plan.role) {
        DataClassRole.fragment =>
          'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`.',
        DataClassRole.nested => '${_field(plan.ownerName, plan.ownerMember)}.',
        DataClassRole.variant =>
          '[${plan.baseName}] when its type is `${plan.variantTypeName}`.',
        DataClassRole.unknownVariant =>
          '[${plan.baseName}] when its type is none of those the selection '
              'tells apart.',
        DataClassRole.operationData => throw StateError(
          '${plan.name} is a ${plan.role.name} class.',
        ),
      };

  /// The doc of the sealed base [plan]; see [of] for [fragmentName].
  String ofBase(PolymorphicBasePlan plan, {String? fragmentName}) {
    final String subject = plan.role == DataClassRole.fragment
        ? 'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`'
        : _field(plan.ownerName, plan.ownerMember);
    return _wrapped(
      '$subject: a class per type the selection tells apart, and '
      '[${plan.unknownName}] for any other type.',
    );
  }

  // A comment line is `/// ` and up to 76 characters.
  String _wrapped(String text) {
    final lines = <String>[];
    var current = '';
    for (final String word in text.split(' ')) {
      if (current.isNotEmpty && current.length + 1 + word.length > 76) {
        lines.add(current);
        current = word;
      } else {
        current = current.isEmpty ? word : '$current $word';
      }
    }
    return [...lines, current].join('\n');
  }

  // The sentence without its end: it names the field of the owner.
  String _field(String? ownerName, String? member) {
    final PlannedField? field = ownerName == null || member == null
        ? null
        : _fieldOf(ownerName, member);
    if (field == null) {
      throw StateError('The owner field $member of $ownerName is not planned.');
    }
    final String subject = '`${field.responseName}` of [$ownerName]';
    return _isList(field.type)
        ? 'The items of the field $subject'
        : 'The field $subject';
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
