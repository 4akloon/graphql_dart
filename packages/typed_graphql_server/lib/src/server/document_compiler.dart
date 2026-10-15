import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'diagnostic_errors.dart';
import 'document_result.dart';

/// Parses and validates one document text against the server's schema.
///
/// Not final: tests subclass it to count the compilations.
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

  /// The result for [text], whose SHA-256 is [hash]: the validated document,
  /// or the errors of the first stage that failed.
  DocumentResult compile(String text, String hash) {
    final source = Source(text);
    return switch (parser.parse(source)) {
      ParseFailure(:final diagnostics) => _rejected(diagnostics),
      ParseSuccess(:final document) => switch (validator.validate(
        schema,
        document,
        source: source,
      )) {
        final ValidDocument valid => DocumentAccepted(valid, source, hash),
        InvalidDocument(:final diagnostics) => _rejected(diagnostics),
      },
    };
  }

  // Unmodifiable: the cache hands the same list to every request, and an
  // extension must not be able to change what later requests see.
  DocumentRejected _rejected(List<Diagnostic> diagnostics) => DocumentRejected(
    List.unmodifiable(const DiagnosticErrors().of(diagnostics)),
  );
}
