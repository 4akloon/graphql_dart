import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'field_lane.dart';
import 'output_ref.dart';

/// A field of an object or interface type, with the way it is resolved.
///
/// `P` is the parent's Dart type and `C` the context type; both are checked
/// where the resolver is wrapped, so a definition carries no cast target.
///
/// {@category builder}
final class FieldDef<P, C> {
  /// Declares the field [name] of type [type].
  FieldDef({
    required this.name,
    required this.type,
    required List<Arg<Object?>> args,
    required List<AppliedDirective> directives,
    required this.lane,
    this.description,
    this.deprecationReason,
  }) : args = List.unmodifiable(args),
       directives = List.unmodifiable(directives);

  /// The field's name in the schema.
  final String name;

  /// The field's output type.
  final OutputRef<Object?> type;

  /// The declared arguments, in declaration order.
  final List<Arg<Object?>> args;

  /// The field's description, null when it has none.
  final String? description;

  /// Why the field is deprecated, null when it is not.
  final String? deprecationReason;

  /// The directives applied to the field, besides `@deprecated`.
  final List<AppliedDirective> directives;

  /// How the field produces its value.
  final FieldLane lane;
}
