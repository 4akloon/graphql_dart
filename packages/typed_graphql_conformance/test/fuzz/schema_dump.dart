import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// Every part of a schema but its spans as lines of text, so two schemas
/// compare equal exactly when they hold the same elements. Type
/// references and values are written by the language [Printer]; the SDL
/// printer is what the round trip tests, so the dump does not use it.
final class SchemaDump {
  /// Creates the dump; it keeps no state.
  const SchemaDump();

  static const Printer _printer = Printer();

  /// The lines of [schema].
  List<String> of(Schema schema) => [
    'roots ${schema.queryTypeName} ${schema.mutationTypeName} '
        '${schema.subscriptionTypeName}',
    ..._described('schema', schema.description, schema.appliedDirectives),
    for (final directive in schema.directives) ..._directive(directive),
    for (final type in schema.types) ..._type(type),
  ];

  List<String> _type(SchemaType type) => [
    ..._described(
      '${type.runtimeType} ${type.name}',
      type.description,
      type.appliedDirectives,
    ),
    ...switch (type) {
      ScalarType() => const <String>[],
      ObjectType(:final interfaces, :final fields) ||
      InterfaceType(:final interfaces, :final fields) => [
        'implements ${interfaces.map(_printer.print).join(' & ')}',
        for (final field in fields) ..._field(field),
      ],
      UnionType(:final memberTypes) => [
        'members ${memberTypes.map(_printer.print).join(' | ')}',
      ],
      EnumType(:final values) => [
        for (final value in values)
          ..._described(
            'value ${value.name}',
            value.description,
            value.appliedDirectives,
          ),
      ],
      InputObjectType(:final fields) => [
        for (final field in fields) ..._inputValue(field),
      ],
    },
  ];

  List<String> _directive(SchemaDirective directive) => [
    ..._described(
      'directive ${directive.name} repeatable ${directive.isRepeatable} '
      'on ${directive.locations.map((location) => location.spelling).join(' | ')}',
      directive.description,
      directive.appliedDirectives,
    ),
    for (final argument in directive.arguments) ..._inputValue(argument),
  ];

  List<String> _field(SchemaField field) => [
    ..._described(
      'field ${field.name}: ${_printer.print(field.type)}',
      field.description,
      field.appliedDirectives,
    ),
    for (final argument in field.arguments) ..._inputValue(argument),
  ];

  List<String> _inputValue(InputValue value) => _described(
    'input ${value.name}: ${_printer.print(value.type)} = '
    '${switch (value.defaultValue) {
      final defaultValue? => _printer.print(defaultValue),
      null => 'none',
    }}',
    value.description,
    value.appliedDirectives,
  );

  /// The [header] of an element, its description and its directives.
  List<String> _described(
    String header,
    String? description,
    List<AppliedDirective> directives,
  ) => [
    header,
    '  description ${jsonEncode(description)}',
    for (final directive in directives)
      '  @${directive.name}'
          '(${directive.arguments.map(_printer.print).join(', ')})',
  ];
}
