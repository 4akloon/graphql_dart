import '../../language/ast/directive_location.dart';
import '../build/built_ins.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'enum_rules.dart';
import 'field_rules.dart';
import 'input_object_rules.dart';
import 'interface_rules.dart';
import 'name_rules.dart';
import 'union_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the named types of a schema (spec §3.4–§3.10), type by
/// type in declaration order, as graphql-js's `validateTypes`: each type
/// is checked by the rule family of its kind.
final class TypeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the declared types of [schema].
  void check() {
    _definitions();
    for (final type in schema.types) {
      NameRules(report).check(type.name, type.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(type.appliedDirectives, _locationOf(type));
      _kind(type);
    }
  }

  void _kind(SchemaType type) {
    switch (type) {
      case ObjectType(:final fields, :final interfaces) ||
          InterfaceType(:final fields, :final interfaces):
        FieldRules(report, schema).check(type, fields);
        InterfaceRules(report, schema).check(interfaces);
      case UnionType():
        UnionRules(report, schema).check(type);
      case EnumType():
        EnumRules(report, schema).check(type);
      case InputObjectType():
        InputObjectRules(report, schema).check(type);
      case ScalarType():
        break;
    }
  }

  static DirectiveLocation _locationOf(SchemaType type) => switch (type) {
    ScalarType() => .scalar,
    ObjectType() => .object,
    InterfaceType() => .interface,
    UnionType() => .union,
    EnumType() => .enumType,
    InputObjectType() => .inputObject,
  };

  // The builder drops these from SDL; a schema built in code may hold
  // them.
  void _definitions() {
    for (final type in schema.types) {
      if (const BuiltIns().typeNamed(type.name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "${type.name}" cannot be redefined.',
          [type.span],
        );
      }
    }
    UniqueNames(report).check(
      [for (final type in schema.types) (type.name, type.span)],
      .duplicateTypeName,
      (name) => 'There can be only one type named "$name".',
    );
  }
}
