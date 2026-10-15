import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization.dart';
import '../execution/field_info.dart';
import '../execution/field_middleware.dart';
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
  }) : this._(name, type, args, description, null, const [], const [], null);

  FieldStub._(
    this.name,
    this.type,
    this._args,
    this.description,
    this._deprecationReason,
    this._directives,
    this._middleware,
    this._authorization,
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
  final List<FieldMiddleware<C>> _middleware;
  final Authorization? _authorization;

  /// The same field, deprecated for [reason].
  FieldStub<P, R, C> deprecated(String reason) => FieldStub._(
    name,
    type,
    _args,
    description,
    reason,
    _directives,
    _middleware,
    _authorization,
  );

  /// The same field with [directives] applied after the ones already given.
  FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives) =>
      FieldStub._(
        name,
        type,
        _args,
        description,
        _deprecationReason,
        [
          ..._directives,
          ...directives,
        ],
        _middleware,
        _authorization,
      );

  /// The same field with [middleware] after the ones already given.
  ///
  /// They run inside the global middleware and outside the directive ones,
  /// the first of the list outermost (spec 8). A pure field has no chain:
  /// combining it with middleware is an [ArgumentError].
  FieldStub<P, R, C> withMiddleware(List<FieldMiddleware<C>> middleware) =>
      FieldStub._(
        name,
        type,
        _args,
        description,
        _deprecationReason,
        _directives,
        [..._middleware, ...middleware],
        _authorization,
      );

  /// The same field under [authorization], replacing a rule given before.
  ///
  /// The rule wins over the object type's (`ObjectOptions.authorization`).
  /// A field that needs the authorizer is checked before its middleware,
  /// whichever lane it has, and a build without an authorizer fails
  /// (`GQL304`). On an interface field the rule guards the implementations
  /// that inherit the field; an object that declares the field itself is
  /// not guarded by it.
  FieldStub<P, R, C> withAuthorization(Authorization authorization) =>
      FieldStub._(
        name,
        type,
        _args,
        description,
        _deprecationReason,
        _directives,
        _middleware,
        authorization,
      );

  /// Completes the field with a synchronous getter (the pure lane, R4.2).
  ///
  /// A pure field has no arguments: giving `args` to the field as well is an
  /// [ArgumentError].
  FieldDef<P, C> pure(R Function(P parent) read) {
    if (_args.isNotEmpty) {
      throw ArgumentError(
        'Field "$name" gives args and pure; a pure getter reads no '
        'arguments, use resolve or resolveWith.',
      );
    }
    if (_middleware.isNotEmpty) {
      throw ArgumentError(
        'Field "$name" gives middleware and pure; a pure getter has no '
        'middleware chain, use resolve.',
      );
    }
    return _define(PureLane((parent) => read(parent as P)), _args);
  }

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

  /// Completes a subscription root field whose events are the field's
  /// values: each item of the stream [source] returns is completed as the
  /// value of the field (spec 10).
  ///
  /// [source] may answer with a future of the stream. Global and field
  /// middleware do not wrap it; they wrap the per-event resolution.
  FieldDef<P, C> subscribe(
    FutureOr<Stream<R>> Function(
      P parent,
      Arguments args,
      C context,
      FieldInfo info,
    )
    source,
  ) => subscribeWith<R>(source, (event, args, context, info) => event);

  /// Completes a subscription root field whose events of type `E` are turned
  /// into the field's value by [resolve] (spec 10).
  ///
  /// [source] may answer with a future of the stream. [resolve] is the
  /// field's resolver: global and field middleware wrap it, once per event.
  FieldDef<P, C> subscribeWith<E>(
    FutureOr<Stream<E>> Function(
      P parent,
      Arguments args,
      C context,
      FieldInfo info,
    )
    source,
    FutureOr<R> Function(E event, Arguments args, C context, FieldInfo info)
    resolve,
  ) => _define(
    SubscribeLane(
      (parent, arguments, context, info) =>
          source(parent as P, arguments, context as C, info),
      (event, arguments, context, info) =>
          resolve(event as E, arguments, context as C, info),
    ),
    _args,
  );

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
    middleware: _middleware,
    authorization: _authorization,
  );
}
