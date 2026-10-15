/// The access rule of a field or of every field of an object type (R4.19).
///
/// A rule is data: the `Authorizer` decides what the requirements mean.
///
/// {@category authorization}
sealed class Authorization {
  const Authorization();

  /// A field anyone may read: the authorizer is not called, and the field
  /// counts as covered by `AuthorizationCoverage`.
  const factory Authorization.public() = PublicAuthorization;

  /// A field guarded by the authorizer, which receives [requirements] (for
  /// example roles or scopes) with every access.
  factory Authorization.requires(List<String> requirements) =
      RequiredAuthorization;
}

/// The rule of a field anyone may read.
///
/// {@category authorization}
final class PublicAuthorization extends Authorization {
  /// Creates the rule.
  const PublicAuthorization();
}

/// The rule of a field the authorizer guards.
///
/// {@category authorization}
final class RequiredAuthorization extends Authorization {
  /// Creates the rule with a copy of [requirements].
  RequiredAuthorization(List<String> requirements)
    : requirements = List.unmodifiable(requirements);

  /// What the authorizer is told the field needs.
  final List<String> requirements;
}
