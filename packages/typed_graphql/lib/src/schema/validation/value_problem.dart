import '../../language/ast/node.dart';

/// Why a constant value is not a value of its input type: a message, the
/// node it is about and the path to that node inside the value.
final class ValueProblem(
  /// graphql-js's `validateInputLiteral` message.
  final String message,

  /// The node the problem is about: the value, an item, a field.
  final Node node,
  List<Object> path,
) {
  /// Creates a problem.
  this;

  /// The keys from the whole value to [node]: input field names
  /// ([String]) and list indexes ([int]).
  final List<Object> path = List.unmodifiable(path);

  /// The path as graphql-js's `printPathArray` prints it, `' at .a[0]'`;
  /// empty for the whole value.
  String get pathText => [
    if (path.isNotEmpty) ' at ',
    for (final key in path)
      switch (key) {
        int() => '[$key]',
        _ => '.$key',
      },
  ].join();
}
