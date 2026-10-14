import '../diagnostics/diagnostic.dart';
import '../language/ast/document.dart';
import '../schema/validation/schema_validation_result.dart';

/// The result of validating a document against a schema:
/// [ValidDocument] or [InvalidDocument] (R3.4). An invalid document never
/// throws.
///
/// {@category validation}
sealed class DocumentValidationResult {
  /// Creates a result.
  const DocumentValidationResult();

  /// The schema the document was validated against.
  ValidSchema get schema;

  /// The document that was validated.
  Document get document;

  /// The problems found, in report order; empty for a [ValidDocument].
  List<Diagnostic> get diagnostics;
}

/// A document that passed every rule of a run, bound to the schema it was
/// validated against (R3.4).
///
/// Only `DocumentValidator.validate` and [ValidDocument.assumeValid] make
/// one, so the executor knows the document was checked; it also checks that
/// [schema] is the schema it executes against.
///
/// {@category validation}
final class ValidDocument extends DocumentValidationResult {
  const ValidDocument._(this.schema, this.document);

  /// Binds [document] to [schema] without validating it, for a document
  /// known to be valid, such as a trusted document checked when it was
  /// registered; nothing checks it.
  factory ValidDocument.assumeValid(ValidSchema schema, Document document) =>
      ValidDocument._(schema, document);

  @override
  final ValidSchema schema;

  @override
  final Document document;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A document that breaks at least one rule of a run.
///
/// {@category validation}
final class InvalidDocument(
  @override final ValidSchema schema,
  @override final Document document,
  List<Diagnostic> diagnostics,
) extends DocumentValidationResult {
  /// Creates the result of validating [document].
  this : assert(diagnostics.isNotEmpty, 'an invalid document has a problem');

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
