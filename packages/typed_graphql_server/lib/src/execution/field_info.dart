import 'package:typed_graphql/typed_graphql.dart';

import 'response_path.dart';

/// What a resolver knows about the call it answers.
///
/// {@category execution}
final class FieldInfo {
  /// Describes the call of [fieldName] on [parentType] at [path].
  FieldInfo({
    required this.fieldName,
    required this.parentType,
    required this.returnType,
    required this.path,
    required this.fieldNodes,
    required this.operation,
    required this.variables,
    required this.schema,
    this.rootValue,
  });

  /// The field's name in the schema.
  final String fieldName;

  /// The object type the field is selected on.
  final ObjectType parentType;

  /// The field's declared type.
  final TypeRef returnType;

  /// The response path of the field, from the root.
  final ResponsePath path;

  /// The field nodes merged under the response key, in document order; do
  /// not change the list.
  final List<Field> fieldNodes;

  /// The operation being executed.
  final OperationDefinition operation;

  /// The request's variable values as sent, before coercion.
  final JsonObject variables;

  /// The schema being executed.
  final ValidSchema schema;

  /// The root value of the execution.
  final Object? rootValue;

  /// The name of the object type the field is selected on.
  String get parentTypeName => parentType.name;
}
