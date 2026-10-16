import '../introspection/introspection_policy.dart';
import 'csrf_prevention.dart';
import 'server_limits.dart';

/// Every protection of a server in one value (R5.4, R5.15).
///
/// {@category server}
final class ServerProfile {
  /// Creates a profile from its protections.
  const ServerProfile({
    required this.introspection,
    required this.includesSuggestions,
    required this.maskErrors,
    required this.csrfPrevention,
    required this.limits,
    this.timeout,
    this.graphiql = false,
  });

  /// Open for development: introspection and suggestions on, errors
  /// unmasked, few limits.
  static const ServerProfile development = ServerProfile(
    introspection: .enabled,
    includesSuggestions: true,
    maskErrors: false,
    csrfPrevention: CsrfPrevention(),
    limits: .development,
    graphiql: true,
  );

  /// Closed for production: introspection and suggestions off, errors
  /// masked, CSRF prevention on, and the limits of [ServerLimits.production]
  /// (document length, tokens, depth, aliases, directives and cost) and no
  /// GraphiQL page. It sets
  /// no [timeout]: add one with [withTimeout]. `GraphQLServer` defaults to it.
  static const ServerProfile production = ServerProfile(
    introspection: .disabled,
    includesSuggestions: false,
    maskErrors: true,
    csrfPrevention: CsrfPrevention(),
    limits: .production,
  );

  /// Whether `__schema` and `__type` are answered.
  final IntrospectionPolicy introspection;

  /// Whether validation messages suggest names ("Did you mean").
  final bool includesSuggestions;

  /// Whether an unexpected error is reported as `GQL330` without its text.
  final bool maskErrors;

  /// The CSRF rule; null is off.
  final CsrfPrevention? csrfPrevention;

  /// The size limits.
  final ServerLimits limits;

  /// The time an execution may take; null is no limit.
  final Duration? timeout;

  /// Whether `GraphQLHttpHandler` serves the GraphiQL page to a browser that
  /// opens the endpoint.
  final bool graphiql;

  /// A copy with [introspection].
  ServerProfile withIntrospection(IntrospectionPolicy introspection) =>
      _copy(introspection: introspection);

  /// A copy with [includesSuggestions].
  ServerProfile withSuggestions(bool includesSuggestions) =>
      _copy(includesSuggestions: includesSuggestions);

  /// A copy with [maskErrors].
  ServerProfile withErrorMasking(bool maskErrors) =>
      _copy(maskErrors: maskErrors);

  /// A copy with [csrfPrevention]; null turns the rule off.
  ServerProfile withCsrfPrevention(CsrfPrevention? csrfPrevention) =>
      ServerProfile(
        introspection: introspection,
        includesSuggestions: includesSuggestions,
        maskErrors: maskErrors,
        csrfPrevention: csrfPrevention,
        limits: limits,
        timeout: timeout,
        graphiql: graphiql,
      );

  /// A copy with [limits].
  ServerProfile withLimits(ServerLimits limits) => _copy(limits: limits);

  /// A copy with [timeout]; null removes the limit.
  ServerProfile withTimeout(Duration? timeout) => ServerProfile(
    introspection: introspection,
    includesSuggestions: includesSuggestions,
    maskErrors: maskErrors,
    csrfPrevention: csrfPrevention,
    limits: limits,
    timeout: timeout,
    graphiql: graphiql,
  );

  /// A copy with [graphiql].
  ServerProfile withGraphiQL(bool graphiql) => _copy(graphiql: graphiql);

  // Copies the non-nullable fields; the two nullable ones, which a caller
  // may set to null, are copied by their own methods above.
  ServerProfile _copy({
    IntrospectionPolicy? introspection,
    bool? includesSuggestions,
    bool? maskErrors,
    ServerLimits? limits,
    bool? graphiql,
  }) => ServerProfile(
    introspection: introspection ?? this.introspection,
    includesSuggestions: includesSuggestions ?? this.includesSuggestions,
    maskErrors: maskErrors ?? this.maskErrors,
    csrfPrevention: csrfPrevention,
    limits: limits ?? this.limits,
    timeout: timeout,
    graphiql: graphiql ?? this.graphiql,
  );

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.introspection == introspection &&
      other.includesSuggestions == includesSuggestions &&
      other.maskErrors == maskErrors &&
      other.csrfPrevention == csrfPrevention &&
      other.limits == limits &&
      other.timeout == timeout &&
      other.graphiql == graphiql;

  @override
  int get hashCode => Object.hash(
    introspection,
    includesSuggestions,
    maskErrors,
    csrfPrevention,
    limits,
    timeout,
    graphiql,
  );
}
