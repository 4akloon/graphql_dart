import '../builder/arguments.dart';
import '../execution/field_info.dart';

/// What an `Authorizer` is asked about: one call of one guarded field.
///
/// {@category authorization}
final class FieldAccess<C> {
  /// Describes the access of the field [info] names on [parent].
  FieldAccess({
    required this.parent,
    required this.arguments,
    required this.context,
    required this.info,
    required this.requirements,
  });

  /// The value the field is read from.
  final Object? parent;

  /// The field's coerced arguments.
  final Arguments arguments;

  /// The request's context.
  final C context;

  /// The call, with its look-ahead (`info.selection`).
  final FieldInfo info;

  /// What the field's rule requires.
  final List<String> requirements;
}
