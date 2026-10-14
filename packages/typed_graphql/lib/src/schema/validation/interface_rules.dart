import '../model/named_type_reference.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of the interfaces an object or interface type implements
/// (spec §3.6, §3.7): each names a known type.
final class InterfaceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [interfaces], the interfaces of one type.
  void check(List<NamedTypeReference> interfaces) {
    for (final reference in interfaces) {
      TypeReferenceRules(
        report,
        schema,
      ).isKnown(reference.name, reference.span);
    }
  }
}
