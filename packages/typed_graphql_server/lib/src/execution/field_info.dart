import 'package:typed_graphql/typed_graphql.dart';

/// What a resolver knows about the call it answers.
///
/// {@category execution}
final class FieldInfo {
  /// Describes the call of [fieldName] on [parentTypeName] at [path].
  FieldInfo({
    required this.fieldName,
    required this.parentTypeName,
    required List<PathSegment> path,
  }) : path = List.unmodifiable(path);

  /// The field's name in the schema.
  final String fieldName;

  /// The name of the object type the field is selected on.
  final String parentTypeName;

  /// The response path of the field, from the root.
  final List<PathSegment> path;
}
