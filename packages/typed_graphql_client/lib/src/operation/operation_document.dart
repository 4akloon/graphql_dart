import 'package:typed_graphql/typed_graphql.dart';

/// The document of a generated operation as it is sent (R7.9): the
/// operation and every fragment it uses, minified, with `__typename` added
/// to every selection of an object.
///
/// {@category operations}
final class const OperationDocument({
  /// The operation's name.
  required final String name,

  /// Whether it is a query, a mutation or a subscription.
  required final OperationType type,

  /// The minified document text.
  required final String text,

  /// The SHA-256 of [text] in UTF-8, in lowercase hexadecimal: the
  /// persisted query id (APQ, trusted documents).
  required final String sha256,
}) {
  /// Creates the document of the operation [name].
  this;
}
