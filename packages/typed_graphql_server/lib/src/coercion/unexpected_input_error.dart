import 'package:typed_graphql/typed_graphql.dart';

/// An error thrown by user code while coercing input, with the error that
/// stands for it in the response.
final class UnexpectedInputError(
  /// What was thrown.
  final Object error,

  /// Where it was thrown.
  final StackTrace stackTrace,

  /// The masked error recorded in the response.
  final GraphQLError reported,
) {
  /// Describes a thrown error.
  this;
}
