import '../../diagnostics/diagnostic.dart';
import '../schema.dart';

/// The result of validating a schema: [ValidSchema] or [InvalidSchema]
/// (spec §7; R2.3). An invalid schema never throws.
///
/// {@category schema}
sealed class SchemaValidationResult {
  /// Creates a result.
  const SchemaValidationResult();

  /// The schema that was validated.
  Schema get schema;

  /// The problems found, in the order the rules report them; empty for a
  /// [ValidSchema].
  List<Diagnostic> get diagnostics;
}

/// A schema that passed every type-system rule, or one a caller trusts.
///
/// Only `SchemaValidator.validate` and [ValidSchema.assumeValid] make
/// one, so code that takes a [ValidSchema] (execution, operation
/// validation) knows the schema was checked.
///
/// {@category schema}
final class ValidSchema extends SchemaValidationResult {
  const ValidSchema._(this.schema);

  /// Wraps [schema] without validating it, for a schema that is known to
  /// be valid, such as one built by generated code; nothing checks it.
  factory ValidSchema.assumeValid(Schema schema) => ValidSchema._(schema);

  @override
  final Schema schema;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A schema that breaks at least one type-system rule.
///
/// {@category schema}
final class InvalidSchema(
  @override final Schema schema,
  List<Diagnostic> diagnostics,
) extends SchemaValidationResult {
  /// Creates the result of validating [schema].
  this : assert(diagnostics.isNotEmpty, 'an invalid schema has a problem');

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
