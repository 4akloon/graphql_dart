import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that a type named by a schema element exists (spec §3.4):
/// the type of a field, an argument or an input field, an implemented
/// interface, a union member or a root type.
///
/// References are names, so the builder keeps an unknown one and this
/// rule reports it, with graphql-js's `KnownTypeNamesRule` message.
final class TypeReferenceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema whose types are known.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Whether [name], written at [span], names a type of [schema];
  /// reports it when not.
  bool isKnown(String name, SourceSpan? span) {
    if (schema.typeNamed(name) != null) {
      return true;
    }
    report.error(.unknownType, 'Unknown type "$name".', [span]);
    return false;
  }

  /// Whether the named type inside [type], held by an element defined at
  /// [element], exists; reports it at the name when not.
  bool isKnownType(TypeRef type, SourceSpan? element) {
    final named = const TypeComparator().namedType(type);
    return isKnown(named.name.value, const NodeSpan().within(element, named));
  }
}
