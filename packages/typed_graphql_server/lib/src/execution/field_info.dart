import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../lookahead/field_selection.dart';
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
    this.selectionReader,
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

  /// Builds [selection] when it is first read; the executor sets it.
  @internal
  final FieldSelection Function()? selectionReader;

  /// The fields the request selected under this field (R4.18), for a
  /// resolver that loads only what is asked for.
  ///
  /// Built when first read, so a resolver that never reads it pays nothing
  /// but the reader's closure; empty for a call made outside an execution.
  // `late`: the reader runs on first read, not when the call starts.
  late final FieldSelection selection =
      selectionReader?.call() ?? FieldSelection.empty;

  /// The name of the object type the field is selected on.
  String get parentTypeName => parentType.name;
}
