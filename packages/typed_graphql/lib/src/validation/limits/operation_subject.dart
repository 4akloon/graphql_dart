import '../../language/ast/executable_definition.dart';

/// How the messages of the limit rules name an operation.
final class OperationSubject(final OperationDefinition operation) {
  /// Creates the subject of [operation].
  this;

  /// `The operation "Q"`, or `The anonymous operation`.
  String get text => switch (operation.name) {
    final name? => 'The operation "${name.value}"',
    null => 'The anonymous operation',
  };
}
