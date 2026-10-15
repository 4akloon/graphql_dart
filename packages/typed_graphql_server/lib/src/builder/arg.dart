import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'optional.dart';
import 'optional_input_ref.dart';

/// A typed argument of a field, or a field of an input object (R4.3).
///
/// A null [defaultValue] means "no default" (spec 3.5): a nullable argument
/// without a value is `null` anyway, and [Arg.optional] tells absence apart.
///
/// {@category builder}
final class Arg<T> {
  /// Declares the argument [name] of type [type].
  Arg(
    this.name,
    this.type, {
    this.defaultValue,
    this.description,
    this.deprecationReason,
  }) : _absentValue = null;

  Arg._optional(
    this.name,
    this.type, {
    this.description,
    this.deprecationReason,
  }) : defaultValue = null,
       _absentValue = const Absent() as T;

  /// Declares an argument whose absence differs from `null`: its value is
  /// [Present] when the request gave one and [Absent] when it did not (R4.4).
  static Arg<Optional<T>> optional<T>(
    String name,
    InputRef<T> type, {
    String? description,
    String? deprecationReason,
  }) => Arg<Optional<T>>._optional(
    name,
    OptionalInputRef(type),
    description: description,
    deprecationReason: deprecationReason,
  );

  /// The argument's name in the schema.
  final String name;

  /// The argument's type.
  final InputRef<T> type;

  /// The value used when the request gives none; null when there is no
  /// default.
  final T? defaultValue;

  /// The description, null when there is none.
  final String? description;

  /// Why the argument is deprecated, null when it is not.
  final String? deprecationReason;

  // What a missing key reads as, before the default is considered.
  final T? _absentValue;

  /// The default value as JSON for the schema, null when there is no default.
  ///
  /// A value the type cannot write is an [ArgumentError] or a [StateError].
  JsonValue? get defaultJson {
    final value = defaultValue;
    return value == null ? null : type.jsonOf(value);
  }

  /// The typed value of this argument in [coerced], a map of coerced values
  /// whose absent keys are absent.
  ///
  /// A required argument cannot be missing once coercion has run, so a
  /// missing one without a default or an absent form is a bug (a `TypeError`
  /// when [T] does not allow null).
  T read(Map<String, Object?> coerced) {
    if (coerced.containsKey(name)) {
      return type.adapt(coerced[name]);
    }
    return (_absentValue ?? defaultValue) as T;
  }
}
