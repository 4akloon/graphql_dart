import 'collected_selection.dart';
import 'planned_field.dart';

/// What a variant class takes from its sealed base.
final class const VariantContext(
  /// The sealed base.
  final String baseName,

  /// The variant's own collection, already made for the sharing decision.
  final CollectedSelection collected,

  /// The base's shared fields, by response name.
  final Map<String, PlannedField> sharedFields,

  /// The base's shared holder, null when the base declares none.
  final String? sharedHolderName,
) {
  /// Creates a context.
  this;
}
