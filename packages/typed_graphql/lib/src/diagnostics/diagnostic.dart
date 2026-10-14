import 'diagnostic_code.dart';
import 'diagnostic_severity.dart';
import 'source_location.dart';
import 'source_span.dart';

/// One problem found in a document, a schema or a payload; immutable.
final class Diagnostic(
  /// The stable code; its [DiagnosticCode.id] appears in messages.
  final DiagnosticCode code,

  /// Whether this is an error or a warning.
  final DiagnosticSeverity severity,

  /// A sentence for people: what is wrong, in the terms of the input.
  final String message, {

  /// Where the problem is; null when it has no place in a source, such as
  /// a problem of a schema built in code.
  final SourceSpan? span,
  List<SourceSpan> related = const [],
}) {
  /// Creates a diagnostic.
  this;

  /// Other places that explain the problem, such as the first definition
  /// of a duplicated name, in the order the GraphQL error's `locations`
  /// list them after [span].
  final List<SourceSpan> related = List.unmodifiable(related);

  /// Whether [severity] is [DiagnosticSeverity.error].
  bool get isError => severity == .error;

  /// The line and column of [span] and then of each [related] span: the
  /// `locations` of the GraphQL error this diagnostic becomes.
  List<SourceLocation> get locations => [
    ?span?.location,
    for (final place in related) place.location,
  ];

  /// `name:line:column: severity GQLnnn: message`, without the place when
  /// there is no [span]: the form a terminal links to the source.
  @override
  String toString() {
    final place = span == null ? '' : '$span: ';
    return '$place${severity.name} ${code.id}: $message';
  }
}
