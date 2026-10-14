import '../../diagnostics/source.dart';
import '../../language/ast/value.dart';
import '../../language/parser/parse_element_result.dart';
import '../../language/parser/parser.dart';
import '../../protocol/path_segment.dart';
import '../model/input_value.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'type_ref_reader.dart';

/// Reads the fields, input values and enum values of an introspection
/// result (graphql-js's `buildField`, `buildInputValue` and
/// `buildEnumDef`).
///
/// An element with a problem is reported and left out; its siblings are
/// still read.
final class MemberReader(
  /// Reads the type references of the members.
  final TypeRefReader types,
) {
  /// Creates a reader.
  this;

  static const IntrospectionAnnotations _annotations =
      IntrospectionAnnotations();

  /// The fields of [type]; empty, after a report, without a `fields`
  /// array.
  List<SchemaField> fields(IntrospectionObject type) => [
    for (final field in type.list('fields') ?? const <IntrospectionObject>[])
      ?_field(field),
  ];

  /// The input values in [values]: arguments or input fields.
  List<InputValue> inputValues(List<IntrospectionObject> values) => [
    for (final value in values) ?_inputValue(value),
  ];

  /// The values of the enum [type]; empty, after a report, without an
  /// `enumValues` array.
  List<SchemaEnumValue> enumValues(IntrospectionObject type) => [
    for (final value
        in type.list('enumValues') ?? const <IntrospectionObject>[])
      if (value.string('name') case final name?)
        SchemaEnumValue(
          name,
          description: value.optionalString('description'),
          appliedDirectives: _annotations.deprecated(value),
        ),
  ];

  SchemaField? _field(IntrospectionObject field) {
    final name = field.string('name');
    final type = types.read(field, 'type');
    final arguments = field.list('args', what: 'field args');
    if (name == null || type == null || arguments == null) {
      return null;
    }
    return SchemaField(
      name,
      type,
      description: field.optionalString('description'),
      arguments: inputValues(arguments),
      appliedDirectives: _annotations.deprecated(field),
    );
  }

  InputValue? _inputValue(IntrospectionObject value) {
    final name = value.string('name');
    final type = types.read(value, 'type');
    final defaultValue = _defaultValue(value);
    if (name == null || type == null || defaultValue == null) {
      return null;
    }
    return InputValue(
      name,
      type,
      description: value.optionalString('description'),
      defaultValue: defaultValue.value,
      appliedDirectives: _annotations.deprecated(value),
    );
  }

  /// The parsed `defaultValue` of [element], a null value without one;
  /// null itself, after a report, when it is not a constant GraphQL value.
  ({Value? value})? _defaultValue(IntrospectionObject element) {
    final text = element.optionalString('defaultValue');
    if (text == null) {
      return (value: null);
    }
    final parsed = const Parser().parseValue(Source(text), isConst: true);
    switch (parsed) {
      case ParseElementSuccess(:final value):
        return (value: value);
      case ParseElementFailure(:final diagnostics):
        element.report(
          .malformedIntrospectionMember,
          'Default value is not a constant GraphQL value: '
          '${diagnostics.first.message}',
          inside: const [PathKey('defaultValue')],
        );
        return null;
    }
  }
}
