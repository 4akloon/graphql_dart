import 'package:typed_graphql/typed_graphql.dart';

/// What a generated reader needs besides the JSON: the operation's
/// variables, which decide whether a fragment spread under `@include` or
/// `@skip` was selected.
///
/// {@category operations}
final class const DataContext([
  /// The variables the operation was sent with; null when there were none.
  final JsonObject? variables,

  /// The defaults of the operation's Boolean variables, by name, for the
  /// variables that were not sent.
  final Map<String, bool> defaults = const {},
]) {
  /// Creates the context of an operation sent with [variables].
  this;

  /// The value of the Boolean variable [name]: as sent, else its default,
  /// else false (validation lets only a variable that is non-null or has a
  /// default stand in `@include(if:)` and `@skip(if:)`).
  bool flag(String name) => switch (variables?[name]) {
    JsonBool(:final value) => value,
    _ => defaults[name] ?? false,
  };
}
