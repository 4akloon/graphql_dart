import '../../diagnostics/diagnostic.dart';
import '../schema.dart';

/// The result of building a schema: [BuildSuccess] or [BuildFailure]
/// (spec §4; R0.3). Bad SDL never throws.
///
/// {@category schema}
sealed class const BuildResult() {
  /// Creates a result.
  this;

  /// Every diagnostic of the build, in document order; empty on success.
  List<Diagnostic> get diagnostics;
}

/// A schema built without a construction problem. It is not validated:
/// a reference may still name a type that does not exist. A build reports
/// errors only, so it carries no diagnostics; non-fatal findings are the
/// job of validation.
///
/// {@category schema}
final class BuildSuccess(
  /// The schema.
  final Schema schema,
) extends BuildResult {
  /// Creates a success.
  this;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A build with errors, such as a repeated type name.
///
/// {@category schema}
final class BuildFailure(
  /// Everything that built: what an error is about is left out (the
  /// second of two types with one name, an extension of a missing type).
  /// It can be complete, when the only errors left nothing out (an
  /// unknown type reference, `GQL100`).
  final Schema partial,
  List<Diagnostic> diagnostics,
) extends BuildResult {
  /// Creates a failure.
  this;

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
