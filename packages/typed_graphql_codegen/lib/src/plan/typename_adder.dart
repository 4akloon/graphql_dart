import 'package:typed_graphql/typed_graphql.dart';

/// Appends an unaliased `__typename` to the selection set of every field
/// that has one and lacks it (R7.9): the client reads the type of every
/// object from it.
///
/// Inline fragments and fragment definitions get none; the field around
/// them has it.
final class TypenameAdder extends AstTransformer {
  /// Creates the transformer.
  const TypenameAdder();

  @override
  Node? rewrite(Node node) {
    if (node case Field(:final selectionSet?)
        when !_hasTypename(selectionSet)) {
      return Field(
        node.alias,
        node.name,
        arguments: node.arguments,
        directives: node.directives,
        selectionSet: appendTo(selectionSet),
        start: node.start,
        end: node.end,
      );
    }
    return node;
  }

  /// [selectionSet] with `__typename` last.
  SelectionSet appendTo(SelectionSet selectionSet) => SelectionSet(
    [
      ...selectionSet.selections,
      Field(null, const Name('__typename')),
    ],
    start: selectionSet.start,
    end: selectionSet.end,
  );

  // A `__typename` under `@include` or `@skip` may be missing from the
  // response, so it does not stand in for the added one.
  bool _hasTypename(SelectionSet selectionSet) => selectionSet.selections.any(
    (selection) =>
        selection is Field &&
        selection.alias == null &&
        selection.name.value == '__typename' &&
        !selection.directives.any(
          (directive) =>
              directive.name.value == 'include' ||
              directive.name.value == 'skip',
        ),
  );
}
