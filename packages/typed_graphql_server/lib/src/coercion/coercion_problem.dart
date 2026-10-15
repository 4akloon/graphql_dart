import 'package:typed_graphql/typed_graphql.dart';

/// One reason an input value is invalid: graphql-js's message and the path
/// to the place.
final class CoercionProblem(
  /// What is wrong, as graphql-js words it.
  final String message,

  /// The path text, ` at .a[0]`, empty for the value itself.
  final String where, {

  /// The code of this problem when it is not the caller's default code.
  final DiagnosticCode? code,

  /// The extensions of a `GraphQLException` that caused the problem.
  final JsonObject? extensions,

  /// The error user code threw and its stack trace, which the caller
  /// reports to `onError`; null when the problem is not about a throw.
  final ({Object error, StackTrace stackTrace})? thrown,
}) {
  /// Describes a problem.
  this;
}
