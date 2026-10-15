import 'field_group.dart';
import 'fragment_use.dart';
import 'narrowing.dart';

/// What one level of a selection holds for a parent type.
final class CollectedSelection(
  /// The fields by response name, in first-occurrence order.
  List<FieldGroup> fields,

  /// The fragments selected, in first-occurrence order.
  List<FragmentUse> fragments,

  /// The conditions that narrow an abstract parent, in document order.
  List<Narrowing> narrowings, {

  /// Whether an unaliased `__typename` was selected at this level; it is
  /// not a [FieldGroup].
  final bool selectsTypename = false,
}) {
  /// Creates a collected selection.
  this;

  /// The fields by response name, in first-occurrence order.
  final List<FieldGroup> fields = List.unmodifiable(fields);

  /// The fragments selected, in first-occurrence order.
  final List<FragmentUse> fragments = List.unmodifiable(fragments);

  /// The conditions that narrow an abstract parent, in document order.
  final List<Narrowing> narrowings = List.unmodifiable(narrowings);
}
