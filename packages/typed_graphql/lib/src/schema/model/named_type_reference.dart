import '../../diagnostics/source_span.dart';

/// A reference to a named type by its name, with the place it was
/// written: an interface that a type implements or a member of a union.
///
/// An extension may add a reference from another source than the type's
/// definition, so the reference carries its own span; a diagnostic about
/// it points there (spec §3.4.3).
///
/// {@category schema}
final class const NamedTypeReference(
  /// The name of the type referred to.
  final String name, {

  /// Where the reference was written; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a reference to the type named [name].
  this;
}
