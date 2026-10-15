import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization.dart';
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
  /// Declares the field [name] of type [type]; the builder calls it, so it
  /// is not part of the public API.
  @internal
  FieldDef({
    required this.name,
    required this.type,
    required List<Arg<Object?>> args,
    required List<AppliedDirective> directives,
    required this.lane,
    this.description,
    this.deprecationReason,
    this.authorization,
    List<Object> middleware = const [],
  }) : args = List.unmodifiable(args),
       directives = List.unmodifiable(directives),
       middleware = List.unmodifiable(middleware);

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

  /// How the field produces its value; not part of the public API.
  @internal
  final FieldLane lane;

  /// The `FieldMiddleware<C>` values of the field, erased to [Object]: a
  /// definition read as `FieldDef<Object?, Object?>` must not hold a
  /// `C`-typed function. The build casts them back where `C` is known; not
  /// part of the public API.
  @internal
  final List<Object> middleware;

  /// The authorization rule that applies to the field: its own, else (after
  /// the build) its object type's; null when it has none.
  final Authorization? authorization;

  /// The same field with [lane] and no middleware of its own: the build
  /// stores the composed chain this way. [authorization] replaces the rule
  /// when given.
  FieldDef<P, C> withLane(FieldLane lane, [Authorization? authorization]) =>
      FieldDef(
        name: name,
        type: type,
        args: args,
        directives: directives,
        lane: lane,
        description: description,
        deprecationReason: deprecationReason,
        authorization: authorization ?? this.authorization,
      );
}
