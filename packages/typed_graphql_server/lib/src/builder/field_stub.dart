import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../execution/field_info.dart';
import 'arg.dart';
import 'arguments.dart';
import 'arguments_def.dart';
import 'field_def.dart';
import 'field_lane.dart';
import 'output_ref.dart';

/// A field whose type is fixed and whose resolver is still to come.
///
/// Fixing `R` here, before the resolver closure is inferred, is what makes a
/// closure that returns the wrong type a compile error (spec 3.2). A stub is
/// not a [FieldDef], so a field without a resolver does not compile.
///
/// {@category builder}
final class FieldStub<P, R, C> {
  /// Creates the stub of the field [name] of type [type].
  FieldStub(
    String name,
    OutputRef<R> type, {
    List<Arg<Object?>> args = const [],
    String? description,
  }) : this._(name, type, args, description, null, const []);

  FieldStub._(
    this.name,
    this.type,
    this._args,
    this.description,
    this._deprecationReason,
    this._directives,
  );

  /// The field's name.
  final String name;

  /// The field's type.
  final OutputRef<R> type;

  /// The field's description.
  final String? description;

  final List<Arg<Object?>> _args;
  final String? _deprecationReason;
  final List<AppliedDirective> _directives;

  /// The same field, deprecated for [reason].
  FieldStub<P, R, C> deprecated(String reason) =>
      FieldStub._(name, type, _args, description, reason, _directives);

  /// The same field with [directives] applied after the ones already given.
  FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives) =>
      FieldStub._(name, type, _args, description, _deprecationReason, [
        ..._directives,
        ...directives,
      ]);

  /// Completes the field with a synchronous getter (the pure lane, R4.2).
  FieldDef<P, C> pure(R Function(P parent) read) =>
      _define(PureLane((parent) => read(parent as P)), _args);

  /// Completes the field with a resolver.
  FieldDef<P, C> resolve(
    FutureOr<R> Function(P parent, Arguments args, C context, FieldInfo info)
    resolve,
  ) => _define(
    ResolverLane(
      (parent, arguments, context, info) =>
          resolve(parent as P, arguments, context as C, info),
    ),
    _args,
  );

  /// Completes the field with a resolver that gets an arguments class built
  /// by [definition] (R4.3).
  ///
  /// The field's arguments are those of [definition]: giving `args` to the
  /// field as well is an [ArgumentError].
  FieldDef<P, C> resolveWith<A>(
    ArgumentsDef<A> definition,
    FutureOr<R> Function(P parent, A args, C context, FieldInfo info) resolve,
  ) {
    if (_args.isNotEmpty) {
      throw ArgumentError(
        'Field "$name" gives args and resolveWith; resolveWith declares the '
        'arguments through its ArgumentsDef.',
      );
    }
    return _define(
      ResolverLane(
        (parent, arguments, context, info) => resolve(
          parent as P,
          definition.decode(arguments),
          context as C,
          info,
        ),
      ),
      definition.args,
    );
  }

  /// Completes an interface field that has no resolver: every implementing
  /// object declares it.
  FieldDef<P, C> declareOnly() => _define(const DeclaredOnlyLane(), _args);

  FieldDef<P, C> _define(FieldLane lane, List<Arg<Object?>> args) => FieldDef(
    name: name,
    type: type,
    args: args,
    description: description,
    deprecationReason: _deprecationReason,
    directives: _directives,
    lane: lane,
  );
}
