/// The answer of an `Authorizer`: [Allow] or [Deny].
///
/// {@category authorization}
sealed class AuthorizationDecision {
  const AuthorizationDecision();
}

/// Access is granted: the field runs.
///
/// {@category authorization}
final class Allow extends AuthorizationDecision {
  /// Creates the decision.
  const Allow();
}

/// Access is refused: the field is a `GQL352` error and null propagates as
/// for any field error.
///
/// {@category authorization}
final class Deny extends AuthorizationDecision {
  /// Creates the decision; [message] reaches the client in place of
  /// `Not authorized to access Type.field.`.
  const Deny({this.message});

  /// What the client reads, null for the default message.
  final String? message;
}
