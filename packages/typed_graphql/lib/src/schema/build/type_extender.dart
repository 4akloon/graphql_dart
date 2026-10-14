import '../../diagnostics/source_span.dart';
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_extension.dart';
import '../model/applied_directive.dart';
import '../model/schema_type.dart';
import '../schema.dart';
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

  /// The schema being extended: a member its type has is "already in the
  /// schema", which graphql-js words differently from a repeat.
  final Schema base,
) {
  /// Creates an extender.
  this;

  /// [types] with [extensions] applied, in the order of [types]; an
  /// extension applies to the first type of its name.
  ///
  /// The extensions of one type are grouped first (document order kept) and
  /// the type is rebuilt once, so extending a type N times is linear.
  List<SchemaType> applyAll(
    List<SchemaType> types,
    List<TypeExtension> extensions,
  ) {
    final indexes = <String, int>{};
    for (final (index, type) in types.indexed) {
      indexes.putIfAbsent(type.name, () => index);
    }
    final grouped = <int, List<TypeExtension>>{};
    for (final node in extensions) {
      final name = node.name.value;
      if (const BuiltIns().typeNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "$name" cannot be extended.',
          node.name,
        );
      } else if (indexes[name] case final index?) {
        (grouped[index] ??= []).add(node);
      } else {
        report.error(
          .unknownExtensionTarget,
          'Cannot extend type "$name" because it is not defined.',
          node.name,
        );
      }
    }
    final extended = [...types];
    for (final MapEntry(key: index, value: nodes) in grouped.entries) {
      extended[index] = _extendAll(types[index], nodes);
    }
    return extended;
  }

  /// [type] extended by the [nodes] of its kind, which are in document
  /// order; the others are reported.
  SchemaType _extendAll(SchemaType type, List<TypeExtension> nodes) {
    final matching = <TypeExtension>[];
    for (final node in nodes) {
      if (_isSameKind(type, node)) {
        matching.add(node);
      } else {
        _reportMismatch(type, node);
      }
    }
    if (matching.isEmpty) return type;
    return switch (type) {
      ScalarType() => ScalarType(
        type.name,
        description: type.description,
        appliedDirectives: _directives(type, matching),
        span: type.span,
      ),
      final ObjectType type => _object(type, matching),
      final InterfaceType type => _interface(type, matching),
      UnionType() => UnionType(
        type.name,
        description: type.description,
        appliedDirectives: _directives(type, matching),
        memberTypes: [
          ...type.memberTypes,
          for (final node in matching.whereType<UnionTypeExtension>())
            ..._elements.references(node.types),
        ],
        span: type.span,
      ),
      final EnumType type => _enum(type, matching),
      final InputObjectType type => _inputObject(type, matching),
    };
  }

  bool _isSameKind(SchemaType type, TypeExtension node) =>
      switch ((type, node)) {
        (ScalarType(), ScalarTypeExtension()) ||
        (ObjectType(), ObjectTypeExtension()) ||
        (InterfaceType(), InterfaceTypeExtension()) ||
        (UnionType(), UnionTypeExtension()) ||
        (EnumType(), EnumTypeExtension()) ||
        (InputObjectType(), InputObjectTypeExtension()) => true,
        _ => false,
      };

  void _reportMismatch(SchemaType type, TypeExtension node) {
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
  }

  ObjectType _object(ObjectType type, List<TypeExtension> nodes) => ObjectType(
    type.name,
    description: type.description,
    interfaces: [
      ...type.interfaces,
      for (final node in nodes.whereType<ObjectTypeExtension>())
        ..._elements.references(node.interfaces),
    ],
    appliedDirectives: _directives(type, nodes),
    fields: [
      ...type.fields,
      for (final field in _members<FieldDefinition>(type, nodes))
        _elements.field(field),
    ],
    span: type.span,
  );

  InterfaceType _interface(InterfaceType type, List<TypeExtension> nodes) =>
      InterfaceType(
        type.name,
        description: type.description,
        interfaces: [
          ...type.interfaces,
          for (final node in nodes.whereType<InterfaceTypeExtension>())
            ..._elements.references(node.interfaces),
        ],
        appliedDirectives: _directives(type, nodes),
        fields: [
          ...type.fields,
          for (final field in _members<FieldDefinition>(type, nodes))
            _elements.field(field),
        ],
        span: type.span,
      );

  EnumType _enum(EnumType type, List<TypeExtension> nodes) => EnumType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, nodes),
    values: [
      ...type.values,
      for (final value in _members<EnumValueDefinition>(type, nodes))
        _elements.enumValue(value),
    ],
    span: type.span,
  );

  InputObjectType _inputObject(
    InputObjectType type,
    List<TypeExtension> nodes,
  ) => InputObjectType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, nodes),
    fields: [
      ...type.fields,
      for (final field in _members<InputValueDefinition>(type, nodes))
        _elements.inputValue(field),
    ],
    span: type.span,
  );

  final ElementReader _elements = ElementReader(report.spans);

  List<AppliedDirective> _directives(
    SchemaType type,
    List<TypeExtension> nodes,
  ) => [
    ...type.appliedDirectives,
    for (final node in nodes) ..._elements.appliedAll(node.directives),
  ];

  /// The members of [nodes] that [type] does not have yet, filtered in one
  /// pass so a repeat across two extensions is found.
  Iterable<T> _members<T extends Node>(
    SchemaType type,
    List<TypeExtension> nodes,
  ) {
    final original = base.typeNamed(type.name);
    return MemberFilter(report)
        .members(
          type.name,
          [for (final node in nodes) ...node.children],
          _memberSpans(type),
          inSchema: original == null
              ? const {}
              : {..._memberSpans(original).keys},
        )
        .whereType<T>();
  }

  Map<String, SourceSpan?> _memberSpans(SchemaType type) => switch (type) {
    ObjectType(:final fields) || InterfaceType(:final fields) => {
      for (final field in fields) field.name: field.span,
    },
    EnumType(:final values) => {
      for (final value in values) value.name: value.span,
    },
    InputObjectType(:final fields) => {
      for (final field in fields) field.name: field.span,
    },
    ScalarType() || UnionType() => const {},
  };
}
