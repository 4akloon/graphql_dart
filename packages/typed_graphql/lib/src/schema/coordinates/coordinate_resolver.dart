import '../../language/ast/schema_coordinate.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'coordinate_target.dart';

/// Finds the element a schema coordinate names in [schema] (September2025
/// §2.14, "Resolving a Schema Coordinate").
///
/// Where the specification raises an error (a containing element that is
/// missing or of the wrong kind), the result is null too (spec §9): a
/// coordinate is user input. Meta-fields and introspection types are not
/// schema elements, so their coordinates resolve to null.
final class CoordinateResolver(
  /// The schema the coordinates refer to.
  final Schema schema,
) {
  /// Creates a resolver.
  this;

  /// The element [coordinate] names; null when there is none.
  CoordinateTarget? resolve(SchemaCoordinate coordinate) =>
      switch (coordinate) {
        TypeCoordinate(:final name) => switch (_type(name.value)) {
          final type? => TypeTarget(type),
          null => null,
        },
        MemberCoordinate(:final name, :final memberName) => _member(
          name.value,
          memberName.value,
        ),
        ArgumentCoordinate(
          :final name,
          :final fieldName,
          :final argumentName,
        ) =>
          _argument(name.value, fieldName.value, argumentName.value),
        DirectiveCoordinate(:final name) => switch (schema.directiveNamed(
          name.value,
        )) {
          final directive? => DirectiveTarget(directive),
          null => null,
        },
        DirectiveArgumentCoordinate(:final name, :final argumentName) =>
          _directiveArgument(name.value, argumentName.value),
      };

  // An introspection type is not a schema element (§2.14, note).
  SchemaType? _type(String name) =>
      name.startsWith('__') ? null : schema.typeNamed(name);

  CoordinateTarget? _member(String typeName, String memberName) =>
      switch (_type(typeName)) {
        final EnumType type => switch (type.valueNamed(memberName)) {
          final value? => EnumValueTarget(type, value),
          null => null,
        },
        final InputObjectType type => switch (type.fieldNamed(memberName)) {
          final field? => InputFieldTarget(type, field),
          null => null,
        },
        final type? => switch (_fieldOf(type, memberName)) {
          final field? => FieldTarget(type, field),
          null => null,
        },
        null => null,
      };

  CoordinateTarget? _argument(
    String typeName,
    String fieldName,
    String argumentName,
  ) {
    if (_type(typeName) case final type?) {
      if (_fieldOf(type, fieldName) case final field?) {
        if (field.argumentNamed(argumentName) case final argument?) {
          return ArgumentTarget(type, field, argument);
        }
      }
    }
    return null;
  }

  CoordinateTarget? _directiveArgument(String name, String argumentName) {
    if (schema.directiveNamed(name) case final directive?) {
      if (directive.argumentNamed(argumentName) case final argument?) {
        return DirectiveArgumentTarget(directive, argument);
      }
    }
    return null;
  }

  // Only object and interface types have fields; meta-fields are not in
  // the model, so `__typename` finds nothing.
  SchemaField? _fieldOf(SchemaType type, String name) => switch (type) {
    ObjectType() => type.fieldNamed(name),
    InterfaceType() => type.fieldNamed(name),
    _ => null,
  };
}
