import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';

/// The fields of `__Field`, `__InputValue`, `__EnumValue` and `__Directive`
/// over the core model (September2025 4.2.3 to 4.2.6).
final class MemberLanes {
  /// Creates the lanes.
  MemberLanes();

  /// `__Field` by field name; the parent is a [SchemaField].
  Map<String, FieldDef<Object?, Object?>> get fieldFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaField>('name', (field) => field.name),
        IntrospectionFields.pure<SchemaField>(
          'description',
          (field) => field.description,
        ),
        IntrospectionFields.withArguments<SchemaField>(
          'args',
          (field, arguments) => _inputValues(field.arguments, arguments),
        ),
        IntrospectionFields.pure<SchemaField>(
          'type',
          (field) => IntrospectedType(field.type),
        ),
        ..._deprecation<SchemaField>((field) => field.deprecationReason),
      ]);

  /// `__InputValue` by field name; the parent is an [InputValue].
  Map<String, FieldDef<Object?, Object?>> get inputValueFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<InputValue>('name', (value) => value.name),
        IntrospectionFields.pure<InputValue>(
          'description',
          (value) => value.description,
        ),
        IntrospectionFields.pure<InputValue>(
          'type',
          (value) => IntrospectedType(value.type),
        ),
        IntrospectionFields.pure<InputValue>(
          'defaultValue',
          (value) => switch (value.defaultValue) {
            final defaultValue? => const Printer().print(defaultValue),
            null => null,
          },
        ),
        ..._deprecation<InputValue>((value) => value.deprecationReason),
      ]);

  /// `__EnumValue` by field name; the parent is a [SchemaEnumValue].
  Map<String, FieldDef<Object?, Object?>> get enumValueFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaEnumValue>(
          'name',
          (value) => value.name,
        ),
        IntrospectionFields.pure<SchemaEnumValue>(
          'description',
          (value) => value.description,
        ),
        ..._deprecation<SchemaEnumValue>((value) => value.deprecationReason),
      ]);

  /// `__Directive` by field name; the parent is a [SchemaDirective].
  Map<String, FieldDef<Object?, Object?>> get directiveFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaDirective>(
          'name',
          (directive) => directive.name,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'description',
          (directive) => directive.description,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'isRepeatable',
          (directive) => directive.isRepeatable,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'locations',
          (directive) => directive.locations,
        ),
        IntrospectionFields.withArguments<SchemaDirective>(
          'args',
          (directive, arguments) =>
              _inputValues(directive.arguments, arguments),
        ),
      ]);

  List<InputValue> _inputValues(
    List<InputValue> values,
    Map<String, Object?> arguments,
  ) => [
    for (final value in values)
      if (IntrospectionFields.includesDeprecated(arguments) ||
          value.deprecationReason == null)
        value,
  ];

  List<FieldDef<Object?, Object?>> _deprecation<P>(
    String? Function(P parent) reason,
  ) => [
    IntrospectionFields.pure<P>(
      'isDeprecated',
      (parent) => reason(parent) != null,
    ),
    IntrospectionFields.pure<P>('deprecationReason', reason),
  ];
}
