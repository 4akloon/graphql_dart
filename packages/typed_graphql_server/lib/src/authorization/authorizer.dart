import 'dart:async';

import 'authorization_decision.dart';
import 'field_access.dart';

/// Decides whether a call of a guarded field may run (R4.19).
///
/// Called after the field's arguments are coerced and before its middleware,
/// on every lane, pure getters included; never for a `public` field or an
/// introspection field. An exception it throws is masked like a resolver's.
///
/// {@category authorization}
abstract interface class Authorizer<C> {
  /// The decision on [access]; it may wait.
  FutureOr<AuthorizationDecision> authorize(FieldAccess<C> access);
}
