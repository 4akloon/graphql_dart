import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'list_size_rules.dart';
import 'validation_report.dart';

/// The IBM cost draft's rules for `@cost` and `@listSize`, run only for a
/// schema that includes the cost directives: a weight is a number, `@cost`
/// stays off interface fields, and `@listSize` is consistent with its
/// field. Types are walked in declaration order, then their fields.
final class CostDirectiveRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  static final RegExp _number = RegExp(
    r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$',
  );

  /// Reports the problems of the cost directives applied in the schema.
  void check() {
    for (final type in schema.types) {
      _weights(type.name, type.appliedDirectives);
      switch (type) {
        case ObjectType(:final fields):
          _fields(type, fields, isInterface: false);
        case InterfaceType(:final fields):
          _fields(type, fields, isInterface: true);
        case InputObjectType(:final fields):
          for (final field in fields) {
            _weights('${type.name}.${field.name}', field.appliedDirectives);
          }
        case ScalarType() || UnionType() || EnumType():
          break;
      }
    }
  }

  void _fields(
    SchemaType type,
    List<SchemaField> fields, {
    required bool isInterface,
  }) {
    for (final field in fields) {
      final coordinate = '${type.name}.${field.name}';
      _weights(coordinate, field.appliedDirectives);
      if (isInterface) {
        _misplaced('field', coordinate, field.appliedDirectives);
      }
      ListSizeRules(report, schema).check(coordinate, field);
      for (final argument in field.arguments) {
        _argument(coordinate, argument, isInterface: isInterface);
      }
    }
  }

  void _argument(
    String fieldCoordinate,
    InputValue argument, {
    required bool isInterface,
  }) {
    final coordinate = '$fieldCoordinate(${argument.name}:)';
    _weights(coordinate, argument.appliedDirectives);
    if (isInterface) {
      _misplaced('field argument', coordinate, argument.appliedDirectives);
    }
  }

  void _weights(String coordinate, List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name != 'cost') {
        continue;
      }
      // A weight of another type is already a GQL124 of the directive.
      if (directive.argument('weight') case StringValue(:final value)
          when !_number.hasMatch(value)) {
        report.error(
          .invalidCostWeight,
          'The @cost weight "$value" of "$coordinate" is not a number.',
          [directive.span],
        );
      }
    }
  }

  void _misplaced(
    String what,
    String coordinate,
    List<AppliedDirective> directives,
  ) {
    for (final directive in directives) {
      if (directive.name == 'cost') {
        report.error(
          .misplacedCost,
          '@cost cannot be applied to the interface $what "$coordinate".',
          [directive.span],
        );
      }
    }
  }
}
