import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

/// The validation of a schema, for a validation test.
final class Validated {
  /// Builds [text], which must build without errors, and validates it.
  Validated(String text) : this.schema(Built(text).schema);

  /// Validates [schema].
  Validated.schema(Schema schema)
    : result = const SchemaValidator().validate(schema);

  /// What the validator returned.
  final SchemaValidationResult result;

  /// Each diagnostic as `line:column id message`, with the locations of
  /// its related spans after `|`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      [
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
        for (final related in diagnostic.related) '| ${related.location}',
      ].join(' '),
  ];

  /// The ids of the diagnostics' codes, in order.
  List<String> get codes => [
    for (final diagnostic in result.diagnostics) diagnostic.code.id,
  ];
}
