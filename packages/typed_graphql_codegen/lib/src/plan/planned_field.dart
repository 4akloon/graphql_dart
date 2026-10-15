import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';

/// A field of a planned data class.
final class PlannedField {
  /// Creates a planned field.
  const PlannedField({
    required this.responseName,
    required this.memberName,
    required this.type,
    required this.isConditional,
    this.definition,
    this.className,
  });

  /// Members a data class cannot use for a field: the members of every
  /// generated class and the `typename` getter of a sealed class.
  static const Set<String> reservedMembers = <String>{
    ...DartNames.objectMembers,
    'typename',
  };

  /// The key in the JSON response; `__typename` for a selected one.
  final String responseName;

  /// The Dart member the field is read through.
  final String memberName;

  /// The field's schema type.
  final TypeRef type;

  /// Whether the field may be absent because of a variable condition.
  final bool isConditional;

  /// The schema field, for doc comments; null for `__typename`.
  final SchemaField? definition;

  /// The generated class of a composite field, null for a leaf.
  final String? className;
}
