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

/// An interface field without a resolver: implementations declare it.
final class DeclaredOnlyLane extends FieldLane {
  /// Creates the lane.
  const DeclaredOnlyLane();
}
