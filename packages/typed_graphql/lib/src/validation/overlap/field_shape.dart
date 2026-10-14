import '../../language/ast/type_ref.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/schema.dart';

/// The shape of a field's type for spec §5.3.2 `SameResponseShape`: its
/// list and non-null wrappers and, inside them, the leaf type's name or
/// `{}` for a composite type.
///
/// Two fields' types conflict, as graphql-js's `doTypesConflict` decides,
/// exactly when their shapes differ.
final class const FieldShape(
  /// The schema the types are in.
  final Schema schema,
) {
  /// Creates the shape reader.
  this;

  /// The shape of [definition]'s type; null without a definition, which
  /// conflicts with nothing.
  String? of(SchemaField? definition) {
    if (definition == null) {
      return null;
    }
    final buffer = StringBuffer();
    var type = definition.type;
    while (true) {
      switch (type) {
        case ListType(type: final item):
          buffer.write('[');
          type = item;
        case NonNullType(type: final nullable):
          buffer.write('!');
          type = nullable;
        case NamedType(:final name):
          final named = schema.typeNamed(name.value);
          buffer.write(named?.isLeafType ?? false ? name.value : '{}');
          return buffer.toString();
      }
    }
  }
}
