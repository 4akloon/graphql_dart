import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';

/// The schema element a schema coordinate names (September2025 §2.14), as
/// `Schema.resolve` finds it: one kind per coordinate form, with the
/// elements that contain it.
///
/// Two targets are equal when they are of one kind and hold the same
/// elements; elements compare by identity.
///
/// {@category schema}
sealed class CoordinateTarget {
  /// Creates a target.
  const CoordinateTarget();

  /// The elements it holds, from the outermost in.
  List<Object> get _elements;

  @override
  bool operator ==(Object other) {
    if (other is! CoordinateTarget || other.runtimeType != runtimeType) {
      return false;
    }
    final elements = _elements;
    final others = other._elements;
    for (var index = 0; index < elements.length; index++) {
      if (!identical(elements[index], others[index])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(_elements));
}

/// A named type, `Business`.
///
/// {@category schema}
final class TypeTarget(
  /// The type.
  final SchemaType type,
) extends CoordinateTarget {
  /// Creates the target of [type].
  this;

  @override
  List<Object> get _elements => [type];
}

/// A field of an object or interface type, `Business.name`.
///
/// {@category schema}
final class FieldTarget(
  /// The object or interface type.
  final SchemaType type,

  /// The field.
  final SchemaField field,
) extends CoordinateTarget {
  /// Creates the target of [field] of [type].
  this;

  @override
  List<Object> get _elements => [type, field];
}

/// An argument of a field, `Query.search(criteria:)`.
///
/// {@category schema}
final class ArgumentTarget(
  /// The object or interface type.
  final SchemaType type,

  /// The field.
  final SchemaField field,

  /// The argument.
  final InputValue argument,
) extends CoordinateTarget {
  /// Creates the target of [argument] of [field] of [type].
  this;

  @override
  List<Object> get _elements => [type, field, argument];
}

/// A field of an input object type, `Criteria.filter`.
///
/// {@category schema}
final class InputFieldTarget(
  /// The input object type.
  final InputObjectType type,

  /// The input field.
  final InputValue inputField,
) extends CoordinateTarget {
  /// Creates the target of [inputField] of [type].
  this;

  @override
  List<Object> get _elements => [type, inputField];
}

/// A value of an enum type, `Filter.OPEN_NOW`.
///
/// {@category schema}
final class EnumValueTarget(
  /// The enum type.
  final EnumType type,

  /// The value.
  final SchemaEnumValue enumValue,
) extends CoordinateTarget {
  /// Creates the target of [enumValue] of [type].
  this;

  @override
  List<Object> get _elements => [type, enumValue];
}

/// A directive, `@private`.
///
/// {@category schema}
final class DirectiveTarget(
  /// The directive.
  final SchemaDirective directive,
) extends CoordinateTarget {
  /// Creates the target of [directive].
  this;

  @override
  List<Object> get _elements => [directive];
}

/// An argument of a directive, `@private(scope:)`.
///
/// {@category schema}
final class DirectiveArgumentTarget(
  /// The directive.
  final SchemaDirective directive,

  /// The argument.
  final InputValue argument,
) extends CoordinateTarget {
  /// Creates the target of [argument] of [directive].
  this;

  @override
  List<Object> get _elements => [directive, argument];
}
