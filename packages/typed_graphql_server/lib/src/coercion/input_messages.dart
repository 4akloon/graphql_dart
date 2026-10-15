import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's messages about the shape of an input object, shared by the
/// coercion of JSON values and of literals; only the way the offending
/// value is printed (`found`) differs between them.
final class InputMessages {
  /// Words messages with or without "Did you mean" text.
  const InputMessages({required this.includesSuggestions});

  static const Suggestions _suggestions = Suggestions();

  /// Whether messages suggest names, as graphql-js's do unless
  /// `hideSuggestions` is set.
  final bool includesSuggestions;

  /// A value that is not an object where an input object is expected.
  String notObject(String typeName, String found) =>
      'Expected value of type "$typeName" to be an object, found: $found.';

  /// An object without a required field.
  String missingField(String typeName, String fieldName, String found) =>
      'Expected value of type "$typeName" to include required field '
      '"$fieldName", found: $found.';

  /// An object with a field the type does not declare; [known] are the
  /// declared names.
  String unknownField(
    String typeName,
    String fieldName,
    List<String> known,
    String found,
  ) {
    final suggestion = includesSuggestions
        ? _suggestions.didYouMean(_suggestions.listFor(fieldName, known))
        : '';
    final lead = suggestion.isEmpty ? ', found' : '.$suggestion Found';
    return 'Expected value of type "$typeName" not to include unknown field '
        '"$fieldName"$lead: $found.';
  }

  /// A `@oneOf` object that does not have exactly one non-null field.
  String oneOf(String typeName) =>
      'Within OneOf Input Object type "$typeName", exactly one field '
      'must be specified, and the value for that field must be non-null.';
}
