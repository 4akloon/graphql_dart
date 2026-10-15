import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import 'dart_writer.dart';
import 'data_class_field.dart';
import 'imports.dart';
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
  /// Only the roles [DataClassRole.fragment] and [DataClassRole.nested] are
  /// written here; any other is a [StateError].
  void emit(
    DataClassPlan plan,
    String doc,
    DartWriter writer,
    Imports imports,
  ) {
    if (plan.role != DataClassRole.fragment &&
        plan.role != DataClassRole.nested) {
      throw StateError('${plan.name} is a ${plan.role.name} class.');
    }
    final fields = [
      for (final field in plan.fields)
        DataClassField.of(field, mapper, imports),
    ];
    final String noun = plan.role == DataClassRole.fragment
        ? 'fragment'
        : 'value';
    writer.doc(doc);
    writer.block('final class ${plan.name} implements client.DataObject', () {
      _members(writer, plan, fields, noun);
    });
  }

  void _members(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
  ) {
    final String name = plan.name;
    _constructor(writer, plan, fields, noun);
    writer.line();
    _reader(writer, plan, fields);
    writer.line();
    writer.doc('Reads and writes the $noun.');
    writer.assign(
      'static const client.DataCodec<$name> codec',
      'client.ObjectDataCodec($name._read)',
    );
    for (final field in fields) {
      writer.line();
      writer.assign(
        'static const client.DataCodec<${field.type.type}> ${field.codecName}',
        field.type.codec,
      );
    }
    _fields(writer, plan, fields);
    if (plan.role == DataClassRole.fragment) {
      writer.line();
      _decode(writer, name);
    }
    writer.line();
    _toJson(writer, plan, fields);
    writer.line();
    const ValueMembers().write(writer, name, [
      for (final field in fields) field.valueMember,
      if (plan.holderName != null) const ValueMember('fragments', false),
    ]);
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
      writer.doc(field.doc);
      writer.line('final ${field.type.type} ${field.member};');
    }
    if (plan.holderName case final holder?) {
      writer.line();
      writer.doc('The fragments spread on this value.');
      writer.line('final $holder fragments;');
    }
  }

  void _decode(DartWriter writer, String name) {
    writer
      ..doc(
        'Reads [json], an object the fragment was spread on, in the response\n'
        'to an operation sent with [variables].',
      )
      ..line('static graphql.DecodeResult<$name> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, client.DataContext(variables));');
  }

  void _toJson(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    const ToJsonWriter().write(writer, [
      if (plan.holderName != null) '...fragments.toJson().fields',
      for (final field in fields)
        '${field.keyLiteral}: ${field.codecName}.write(${field.member})',
    ]);
  }
}
