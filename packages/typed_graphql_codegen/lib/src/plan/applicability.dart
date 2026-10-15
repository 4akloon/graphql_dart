import 'package:typed_graphql/typed_graphql.dart';

import 'type_condition_match.dart';

/// Decides how a type condition relates to a parent type (spec §6).
final class const Applicability(
  /// The schema the types are looked up in.
  final Schema schema,
) {
  /// Creates the decision for [schema].
  this;

  /// How [condition] relates to [parent].
  ///
  /// For an abstract parent only a condition that names it, or an interface
  /// it implements, applies: a condition on a union member or on an
  /// interface the current members happen to implement narrows, so a type
  /// added to the schema later is still covered by the shared fields.
  TypeConditionMatch match(String condition, SchemaType parent) {
    if (condition == parent.name) {
      return TypeConditionMatch.applies;
    }
    final target = schema.typeNamed(condition);
    if (target == null) {
      return TypeConditionMatch.never;
    }
    return switch (parent) {
      ObjectType() =>
        schema.possibleTypes(target).any((type) => identical(type, parent))
            ? TypeConditionMatch.applies
            : TypeConditionMatch.never,
      InterfaceType()
          when target is InterfaceType && schema.isSubType(target, parent) =>
        TypeConditionMatch.applies,
      InterfaceType() || UnionType() =>
        schema.typesOverlap(target, parent)
            ? TypeConditionMatch.narrows
            : TypeConditionMatch.never,
      _ => TypeConditionMatch.never,
    };
  }

  /// The possible types of [parent], in `possibleTypes` order, that are
  /// possible types of [condition].
  List<ObjectType> reach(String condition, SchemaType parent) {
    final target = schema.typeNamed(condition);
    if (target == null) {
      return const [];
    }
    final reached = schema.possibleTypes(target);
    return [
      for (final type in schema.possibleTypes(parent))
        if (reached.any((other) => identical(other, type))) type,
    ];
  }
}
