import '../../language/ast/operation_type.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of the root operation types (spec §3.3.1): a query root
/// exists, every root is an object type, and no object type is the root
/// of two operations; graphql-js's `validateRootTypes`.
///
/// A root that names no type is reported as an unknown type.
final class RootTypeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the roots of [schema].
  void check() {
    if (schema.queryTypeName == null) {
      report.error(.missingQueryRootType, 'Query root type must be provided.', [
        schema.span,
      ]);
    }
    final operationsByRoot = <ObjectType, List<OperationType>>{};
    for (final operation in OperationType.values) {
      final name = schema.rootTypeName(operation);
      if (name == null ||
          !TypeReferenceRules(
            report,
            schema,
          ).isKnown(name, schema.rootTypeSpan(operation))) {
        continue;
      }
      switch (schema.typeNamed(name)) {
        case null:
          continue;
        case final ObjectType type:
          operationsByRoot.putIfAbsent(type, () => []).add(operation);
        case final type:
          _notObject(operation, type);
      }
    }
    for (final MapEntry(key: type, value: operations)
        in operationsByRoot.entries) {
      if (operations.length > 1) {
        _shared(type, operations);
      }
    }
  }

  void _notObject(OperationType operation, SchemaType type) {
    final title = switch (operation) {
      .query => 'Query root type must be Object type',
      .mutation => 'Mutation root type must be Object type if provided',
      .subscription => 'Subscription root type must be Object type if provided',
    };
    report.error(
      .rootTypeNotObject,
      '$title, it cannot be ${type.name}.',
      [schema.rootTypeSpan(operation) ?? type.span],
    );
  }

  void _shared(ObjectType type, List<OperationType> operations) {
    final names = [for (final operation in operations) operation.name];
    final list = names.length == 2
        ? names.join(' and ')
        : '${names.take(names.length - 1).join(', ')}, and ${names.last}';
    report.error(
      .sharedRootType,
      'All root types must be different, "${type.name}" type is used as '
      '$list root types.',
      [for (final operation in operations) schema.rootTypeSpan(operation)],
    );
  }
}
