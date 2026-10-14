import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_extension.dart';
import '../model/applied_directive.dart';
import '../model/schema_type.dart';
import 'build_report.dart';
import 'built_ins.dart';
import 'element_reader.dart';
import 'member_filter.dart';

/// Applies type extensions to the types of a schema (spec §3.4.3): the
/// members, interfaces, union members and directives of an extension go
/// after the type's own, in document order; the span stays the
/// definition's.
///
/// An extension of a built-in, of a missing type or of a type of another
/// kind is reported and ignored, with graphql-js's messages
/// (`PossibleTypeExtensionsRule`).
final class TypeExtender(
  /// Receives the errors and gives the spans.
  final BuildReport report,
) {
  /// Creates an extender.
  this;

  /// [types] with [extensions] applied, in the order of [types].
  List<SchemaType> applyAll(
    List<SchemaType> types,
    List<TypeExtension> extensions,
  ) {
    final extended = {for (final type in types.reversed) type.name: type};
    for (final node in extensions) {
      final name = node.name.value;
      if (const BuiltIns().typeNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "$name" cannot be extended.',
          node.name,
        );
      } else if (extended[name] case final type?) {
        extended[name] = _extend(type, node) ?? _mismatch(type, node);
      } else {
        report.error(
          .unknownExtensionTarget,
          'Cannot extend type "$name" because it is not defined.',
          node.name,
        );
      }
    }
    return [for (final type in types) extended[type.name] ?? type];
  }

  SchemaType _mismatch(SchemaType type, TypeExtension node) {
    final kind = switch (node) {
      ScalarTypeExtension() => 'scalar',
      ObjectTypeExtension() => 'object',
      InterfaceTypeExtension() => 'interface',
      UnionTypeExtension() => 'union',
      EnumTypeExtension() => 'enum',
      InputObjectTypeExtension() => 'input object',
    };
    report.error(
      .extensionKindMismatch,
      'Cannot extend non-$kind type "${type.name}".',
      node.name,
      related: type.span,
    );
    return type;
  }

  /// [type] extended by [node]; null when their kinds differ.
  SchemaType? _extend(SchemaType type, TypeExtension node) =>
      switch ((type, node)) {
        (ScalarType(), ScalarTypeExtension()) => ScalarType(
          type.name,
          description: type.description,
          appliedDirectives: _directives(type, node),
          span: type.span,
        ),
        (final ObjectType type, final ObjectTypeExtension node) => _object(
          type,
          node,
        ),
        (final InterfaceType type, final InterfaceTypeExtension node) =>
          _interface(type, node),
        (final UnionType type, final UnionTypeExtension node) => UnionType(
          type.name,
          description: type.description,
          appliedDirectives: _directives(type, node),
          memberTypes: [...type.memberTypes, ...node.types],
          span: type.span,
        ),
        (final EnumType type, final EnumTypeExtension node) => _enum(
          type,
          node,
        ),
        (final InputObjectType type, final InputObjectTypeExtension node) =>
          _inputObject(type, node),
        _ => null,
      };

  ObjectType _object(ObjectType type, ObjectTypeExtension node) => ObjectType(
    type.name,
    description: type.description,
    interfaces: [...type.interfaces, ...node.interfaces],
    appliedDirectives: _directives(type, node),
    fields: [
      ...type.fields,
      for (final field in _members<FieldDefinition>(type, node))
        _elements.field(field),
    ],
    span: type.span,
  );

  InterfaceType _interface(InterfaceType type, InterfaceTypeExtension node) =>
      InterfaceType(
        type.name,
        description: type.description,
        interfaces: [...type.interfaces, ...node.interfaces],
        appliedDirectives: _directives(type, node),
        fields: [
          ...type.fields,
          for (final field in _members<FieldDefinition>(type, node))
            _elements.field(field),
        ],
        span: type.span,
      );

  EnumType _enum(EnumType type, EnumTypeExtension node) => EnumType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, node),
    values: [
      ...type.values,
      for (final value in _members<EnumValueDefinition>(type, node))
        _elements.enumValue(value),
    ],
    span: type.span,
  );

  InputObjectType _inputObject(
    InputObjectType type,
    InputObjectTypeExtension node,
  ) => InputObjectType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, node),
    fields: [
      ...type.fields,
      for (final field in _members<InputValueDefinition>(type, node))
        _elements.inputValue(field),
    ],
    span: type.span,
  );

  ElementReader get _elements => ElementReader(report.spans);

  List<AppliedDirective> _directives(SchemaType type, TypeExtension node) => [
    ...type.appliedDirectives,
    ..._elements.appliedAll(node.directives),
  ];

  /// The members of [node] that [type] does not have yet.
  Iterable<T> _members<T extends Node>(SchemaType type, TypeExtension node) {
    final earlier = switch (type) {
      ObjectType(:final fields) || InterfaceType(:final fields) => {
        for (final field in fields) field.name: field.span,
      },
      EnumType(:final values) => {
        for (final value in values) value.name: value.span,
      },
      InputObjectType(:final fields) => {
        for (final field in fields) field.name: field.span,
      },
      ScalarType() || UnionType() => const <String, Never>{},
    };
    return MemberFilter(
      report,
    ).members(type.name, node.children, earlier).whereType<T>();
  }
}
