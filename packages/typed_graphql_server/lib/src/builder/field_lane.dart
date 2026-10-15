import 'dart:async';

import '../execution/field_info.dart';
import 'arguments.dart';

/// How a field produces its value. The executor switches over the lane.
///
/// The functions take `Object?` for the parent and the context: the wrappers
/// made by `FieldStub` cast them where the types `P` and `C` are known.
sealed class FieldLane {
  const FieldLane();
}

/// A synchronous getter: no arguments, no middleware, no `FieldInfo` (R4.2).
final class PureLane extends FieldLane {
  /// Creates a lane that calls [read].
  const PureLane(this.read);

  /// Reads the value from the parent.
  final Object? Function(Object? parent) read;
}

/// A resolver that gets the arguments, the context and a `FieldInfo`.
final class ResolverLane extends FieldLane {
  /// Creates a lane that calls [resolve].
  const ResolverLane(this.resolve);

  /// Resolves the value, synchronously or not.
  final FutureOr<Object?> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  resolve;
}

/// A subscription root field: a source of events and the resolver run for
/// each event (spec 10).
final class SubscribeLane extends FieldLane {
  /// Creates a lane that opens events with [source] and answers each with
  /// [resolve].
  ///
  /// [executeResolve] is what `execute` calls; it defaults to [resolve].
  const SubscribeLane(
    this.source,
    this.resolve, [
    FutureOr<Object?> Function(
      Object? parent,
      Arguments arguments,
      Object? context,
      FieldInfo info,
    )?
    executeResolve,
  ]) : executeResolve = executeResolve ?? resolve;

  /// Opens the stream of source events (September2025 6.2.3.1), once per
  /// subscription; it may wait before it answers.
  final FutureOr<Stream<Object?>> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  source;

  /// Turns one source event into the field's value (6.2.3.2), run for each
  /// event of a started subscription, which is authorized once
  /// at [source] (spec 18.45).
  final FutureOr<Object?> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  resolve;

  /// What `execute` calls, with the root value as the event: [resolve],
  /// behind the authorization guard when the field has one, because
  /// `execute` never runs [source].
  final FutureOr<Object?> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  executeResolve;
}

/// An interface field without a resolver: implementations declare it.
final class DeclaredOnlyLane extends FieldLane {
  /// Creates the lane.
  const DeclaredOnlyLane();
}
