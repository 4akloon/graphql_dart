import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'diagnostic_errors.dart';
import 'document_entry.dart';

/// Parses and validates one document text against the server's schema.
@internal
class DocumentCompiler {
  /// Creates a compiler that parses with [parser] and validates against
  /// [schema] with [validator].
  const DocumentCompiler(this.parser, this.validator, this.schema);

  /// The parser, with the server's token limit.
  final Parser parser;

  /// The validator, with the server's rules.
  final DocumentValidator validator;

  /// The schema documents are validated against.
  final ValidSchema schema;

  /// The entry for [text], whose SHA-256 is [hash]: the validated document,
  /// or the errors of the first stage that failed.
  DocumentEntry compile(String text, String hash) {
    final source = Source(text);
    return switch (parser.parse(source)) {
      ParseFailure(:final diagnostics) => RejectedEntry(
        hash,
        const DiagnosticErrors().of(diagnostics),
      ),
      ParseSuccess(:final document) => switch (validator.validate(
        schema,
        document,
        source: source,
      )) {
        final ValidDocument valid => AcceptedEntry(hash, valid, source),
        InvalidDocument(:final diagnostics) => RejectedEntry(
          hash,
          const DiagnosticErrors().of(diagnostics),
        ),
      },
    };
  }
}
