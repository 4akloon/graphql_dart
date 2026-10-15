import 'field_def.dart';
import 'field_lane.dart';
import 'interface_type_def.dart';

/// Collects the fields an object or interface type has: its own, then those
/// it inherits from its interfaces (spec 3.7).
final class FieldInheritance() {
  /// Creates the collaborator.
  this;

  /// The fields of a type with [own] fields that lists [interfaces].
  ///
  /// An interface field the type does not declare by name is added after the
  /// own fields, interfaces in listed order, each followed by the interfaces
  /// it lists. A declare-only field is not inherited: the core validator
  /// reports the missing implementation. Walks with its own stack, so an
  /// interface cycle ends (the core validator reports it).
  List<FieldDef<Object?, Object?>> collect(
    List<FieldDef<Object?, Object?>> own,
    List<InterfaceTypeDef<Object?>> interfaces,
  ) {
    final result = <FieldDef<Object?, Object?>>[...own];
    final names = {for (final field in own) field.name};
    final visited = Set<InterfaceTypeDef<Object?>>.identity();
    final pending = interfaces.reversed.toList();
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!visited.add(next)) continue;
      for (final field in next.fields) {
        if (field.lane is DeclaredOnlyLane) continue;
        if (names.add(field.name)) result.add(field);
      }
      pending.addAll(next.interfaces.reversed);
    }
    return List.unmodifiable(result);
  }
}
