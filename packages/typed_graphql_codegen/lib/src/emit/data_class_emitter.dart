import 'package:typed_graphql/typed_graphql.dart';

import '../plan/data_class_role.dart';
import '../plan/flag_defaults.dart';
import '../plan/planned_class.dart';
import '../plan/planned_field.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'data_class_field.dart';
import 'fragment_decode_writer.dart';
import 'imports.dart';
import 'operation_decode_writer.dart';
import 'reader_factory_writer.dart';
import 'to_json_writer.dart';
import 'type_mapper.dart';
import 'value_member.dart';
import 'value_members.dart';

/// Writes the data class of a fragment or of a composite field (spec §7
/// "Data classes", R7.3).
///
/// {@category codegen}
final class DataClassEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const DataClassEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes [plan] with the class doc comment [doc].
  ///
  /// A variant implements its sealed base, which reads it and declares its
  /// shared members. The data class of an operation needs the [operation];
  /// without it, it is a [StateError].
  void emit(
    DataClassPlan plan,
    String doc,
    DartWriter writer,
    Imports imports, {
    OperationDefinition? operation,
  }) {
    if (plan.role == DataClassRole.operationData && operation == null) {
      throw StateError('${plan.name} is a ${plan.role.name} class.');
    }
    final fields = [
      // The unknown variant holds the type name it was read with.
      if (plan.role == DataClassRole.unknownVariant)
        DataClassField.of(_typenameField, mapper, imports),
      for (final field in plan.fields)
        DataClassField.of(field, mapper, imports),
    ];
    final String noun = switch (plan.role) {
      DataClassRole.fragment => 'fragment',
      DataClassRole.operationData => 'data',
      _ => 'value',
    };
    final String implemented = plan.baseName ?? 'client.DataObject';
    writer.doc(doc);
    writer.block('final class ${plan.name} implements $implemented', () {
      _members(writer, plan, fields, noun, operation);
    });
  }

  static const PlannedField _typenameField = PlannedField(
    responseName: '__typename',
    memberName: 'typename',
    type: NonNullType(NamedType(Name('String'))),
    isConditional: false,
    overridesBase: true,
  );

  void _members(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
    OperationDefinition? operation,
  ) {
    final String name = plan.name;
    _constructor(writer, plan, fields, noun);
    writer.line();
    _reader(writer, plan, fields);
    _codecs(writer, plan, fields, noun);
    final Map<String, bool> flagDefaults = operation == null
        ? const {}
        : const FlagDefaults().of(operation);
    _flagDefaults(writer, flagDefaults);
    _typename(writer, plan);
    _fields(writer, plan, fields);
    if (plan.role == DataClassRole.fragment) {
      writer.line();
      const FragmentDecodeWriter().write(writer, name);
    } else if (operation != null) {
      writer.line();
      const OperationDecodeWriter().write(
        writer,
        name,
        operation,
        flagDefaults,
      );
    }
    writer.line();
    _toJson(writer, plan, fields);
    writer.line();
    const ValueMembers().write(writer, name, [
      for (final field in fields) field.valueMember,
      if (plan.holderName != null) const ValueMember('fragments', false),
    ]);
  }

  void _codecs(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
  ) {
    // The sealed base reads a variant.
    if (plan.baseName == null) {
      writer.line();
      writer.doc('Reads and writes the $noun.');
      writer.assign(
        'static const client.DataCodec<${plan.name}> codec',
        'client.ObjectDataCodec(${plan.name}._read)',
      );
    }
    for (final field in fields) {
      writer.line();
      writer.assign(
        'static const client.DataCodec<${field.type.type}> ${field.codecName}',
        field.type.codec,
      );
    }
  }

  void _constructor(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
  ) {
    final bool hasHolder = plan.holderName != null;
    writer.doc('Creates the $noun.');
    if (fields.isEmpty && !hasHolder) {
      writer.line('const ${plan.name}();');
      return;
    }
    writer.items('const ${plan.name}({', [
      for (final field in fields)
        if (!field.isNullable) 'required this.${field.member}',
      if (hasHolder) 'required this.fragments',
      for (final field in fields)
        if (field.isNullable) 'this.${field.member}',
    ], '});');
  }

  void _reader(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    const ReaderFactoryWriter().write(writer, plan.name, [
      for (final field in fields)
        (
          field.member,
          '${field.codecName}.field(json, ${field.keyLiteral}, context)',
        ),
      if (plan.holderName case final holder?)
        ('fragments', '$holder._read(json, context)'),
    ]);
  }

  void _fields(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    for (final field in fields) {
      writer.line();
      _documentation(writer, field.doc, isOverride: field.overridesBase);
      writer.line('final ${field.type.type} ${field.member};');
    }
    if (plan.holderName case final holder?) {
      writer.line();
      _documentation(
        writer,
        'The fragments spread on this value.',
        isOverride: plan.holderOverridesBase,
      );
      writer.line('final $holder fragments;');
    }
  }

  // An overriding member inherits the doc comment of the base's declaration.
  void _documentation(
    DartWriter writer,
    String doc, {
    required bool isOverride,
  }) {
    if (isOverride) {
      writer.line('@override');
    } else {
      writer.doc(doc);
    }
  }

  void _flagDefaults(DartWriter writer, Map<String, bool> defaults) {
    if (defaults.isEmpty) return;
    final entries = [
      for (final MapEntry(:key, :value) in defaults.entries)
        '${const DartStringLiteral().of(key)}: $value',
    ];
    writer.line();
    writer.assign(
      'static const Map<String, bool> _flagDefaults',
      '{${entries.join(', ')}}',
    );
  }

  void _typename(DartWriter writer, DataClassPlan plan) {
    if (plan.variantTypeName case final typeName?) {
      writer.line();
      writer.line('@override');
      writer.line(
        'String get typename => ${const DartStringLiteral().of(typeName)};',
      );
    }
  }

  void _toJson(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    final entries = [
      if (plan.variantTypeName case final typeName?)
        "'__typename': const graphql.JsonString("
            '${const DartStringLiteral().of(typeName)})',
      for (final field in fields)
        '${field.keyLiteral}: ${field.codecName}.write(${field.member})',
    ];
    if (plan.holderName == null) {
      const ToJsonWriter().write(writer, entries);
    } else {
      const ToJsonWriter().writeMerged(
        writer,
        const ['fragments.toJson()'],
        entries: entries,
      );
    }
  }
}
