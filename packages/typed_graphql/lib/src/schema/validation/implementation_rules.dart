import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rules of a type implementing one interface's fields (spec §3.6.3
/// `IsValidImplementation`), as graphql-js's
/// `validateTypeImplementsInterface`: each interface field exists with a
/// covariant type, each of its arguments exists with the same type, an
/// added argument is optional, and a field is deprecated only when the
/// interface field is.
final class ImplementationRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  static const Printer _printer = Printer();

  /// Reports how [type], whose fields are [fields], fails to implement the
  /// fields of [interface].
  void check(
    SchemaType type,
    List<SchemaField> fields,
    InterfaceType interface,
  ) {
    for (final expected in interface.fields) {
      final field = fields.where((f) => f.name == expected.name).firstOrNull;
      if (field == null) {
        report.error(
          .missingInterfaceField,
          'Interface field ${interface.name}.${expected.name} expected but '
          '${type.name} does not provide it.',
          [expected.span, type.span],
        );
        continue;
      }
      _fieldType(type, field, interface, expected);
      _arguments(type, field, interface, expected);
      _deprecation(type, field, interface, expected);
    }
  }

  void _fieldType(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    // An unknown type is reported once, by the type reference rules.
    if (!_isKnown(field.type) ||
        !_isKnown(expected.type) ||
        schema.isTypeSubTypeOf(field.type, expected.type)) {
      return;
    }
    report.error(
      .invalidImplementationFieldType,
      'Interface field ${interface.name}.${expected.name} expects type '
      '${_printer.print(expected.type)} but ${type.name}.${field.name} is '
      'type ${_printer.print(field.type)}.',
      [
        const NodeSpan().within(expected.span, expected.type),
        const NodeSpan().within(field.span, field.type),
      ],
    );
  }

  void _arguments(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    final owner = '${type.name}.${field.name}';
    for (final wanted in expected.arguments) {
      final coordinate = '${interface.name}.${expected.name}(${wanted.name}:)';
      switch (field.argumentNamed(wanted.name)) {
        case null:
          report.error(
            .missingInterfaceArgument,
            'Interface field argument $coordinate expected but $owner does '
            'not provide it.',
            [wanted.span, field.span],
          );
        case final given
            when !const TypeComparator().isEqual(wanted.type, given.type):
          report.error(
            .invalidImplementationArgumentType,
            'Interface field argument $coordinate expects type '
            '${_printer.print(wanted.type)} but $owner(${given.name}:) is '
            'type ${_printer.print(given.type)}.',
            [
              const NodeSpan().within(wanted.span, wanted.type),
              const NodeSpan().within(given.span, given.type),
            ],
          );
        case _:
          break;
      }
    }
    _addedArguments(type, field, interface, expected);
  }

  void _addedArguments(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    final owner = '${type.name}.${field.name}';
    for (final added in field.arguments) {
      if (added.type is NonNullType &&
          added.defaultValue == null &&
          expected.argumentNamed(added.name) == null) {
        report.error(
          .requiredExtraArgument,
          'Argument "$owner(${added.name}:)" must not be required type '
          '"${_printer.print(added.type)}" if not provided by the Interface '
          'field "${interface.name}.${expected.name}".',
          [added.span, expected.span],
        );
      }
    }
  }

  void _deprecation(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    if (field.deprecationReason == null || expected.deprecationReason != null) {
      return;
    }
    final deprecated = field.appliedDirectives
        .where((directive) => directive.name == 'deprecated')
        .first;
    report.error(
      .deprecatedImplementationField,
      'Interface field ${interface.name}.${expected.name} is not deprecated, '
      'so implementation field ${type.name}.${field.name} must not be '
      'deprecated.',
      [deprecated.span, const NodeSpan().within(field.span, field.type)],
    );
  }

  bool _isKnown(TypeRef type) => schema.namedTypeOf(type) != null;
}
