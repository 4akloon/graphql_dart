import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../schema/built.dart';

/// A validated schema to check documents against, for a validation test.
final class Checked {
  /// Builds and validates [sdl]; fails the test when it is not valid.
  Checked(String sdl)
    : schema = switch (const SchemaValidator().validate(Built(sdl).schema)) {
        final ValidSchema valid => valid,
        InvalidSchema(:final diagnostics) => fail('$diagnostics'),
      };

  /// The schema.
  final ValidSchema schema;

  /// [text] parsed without limits and validated with [validator].
  DocumentValidationResult validate(
    String text, {
    DocumentValidator validator = const DocumentValidator(),
  }) {
    final source = Source(text);
    final document = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source).requireDocument();
    return validator.validate(schema, document, source: source);
  }

  /// The diagnostics of [text] checked by [rules], each as `line:column
  /// id message`.
  List<String> errors(String text, List<ValidationRule> rules) => [
    for (final diagnostic in validate(
      text,
      validator: DocumentValidator(rules: rules),
    ).diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];
}
