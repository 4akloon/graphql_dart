/// A public type declared in a Dart file, with its doc comment.
final class PublicType(
  /// The type's name.
  final String name,

  /// The 1-based line of the declaration.
  final int line,

  /// The doc comment, one string per line, without the `///`.
  final List<String> documentation,
) {
  /// Creates a description.
  this;
}

/// Finds the public classes, enums, mixins and typedefs of Dart source.
///
/// The code rules give a library file its types at the top level and a
/// declaration on one line, so a line scan is enough; a type whose name
/// starts with `_` is private and skipped.
final class PublicTypes {
  /// Creates the finder.
  const PublicTypes();

  static final RegExp _declaration = RegExp(
    r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension type)\s+(?:const\s+)?([A-Z]\w*)',
  );

  /// The public types declared in [source], in order.
  List<PublicType> declaredIn(String source) {
    final types = <PublicType>[];
    var documentation = <String>[];
    for (final (index, line) in source.split('\n').indexed) {
      if (line.startsWith('///')) {
        documentation.add(line.substring(3).trim());
      } else if (!line.startsWith('@')) {
        if (_declaration.firstMatch(line) case final match?) {
          types.add(PublicType(match[1]!, index + 1, documentation));
        }
        documentation = [];
      }
    }
    return types;
  }
}
