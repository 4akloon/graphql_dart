import '../../language/ast/type_ref.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';

/// The fields of an input object type, indexed once for a value check:
/// the position of each name in declaration order and the fields a value
/// must give.
///
/// A value of M fields is then checked in time that depends on M and on
/// the required fields, not on a scan of every declared field per name.
final class InputObjectShape {
  /// Indexes the fields of [type].
  InputObjectShape(InputObjectType type)
    : fields = type.fields,
      _indexes = _indexesOf(type.fields),
      requiredIndexes = [
        for (final (index, field) in type.fields.indexed)
          if (field.type is NonNullType && field.defaultValue == null) index,
      ];

  /// The input fields, in declaration order.
  final List<InputValue> fields;

  /// The positions in [fields] of the fields a value must give: non-null
  /// and without a default value.
  final List<int> requiredIndexes;

  // Only for lookups, never iterated.
  final Map<String, int> _indexes;

  /// The position of the field named [name] in [fields]; null when the type
  /// has none. Of two fields with one name the first counts.
  int? indexOf(String name) => _indexes[name];

  static Map<String, int> _indexesOf(List<InputValue> fields) => {
    for (final (index, field) in fields.indexed.toList().reversed)
      field.name: index,
  };
}
