import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'arguments.dart';
import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';

/// An input object type decoded to the Dart class [T] (R4.4).
///
/// It is its own input reference. The coerced value of an input object is the
/// result of [decode].
///
/// {@category builder}
final class InputObjectDef<T extends Object> extends NamedTypeDef
    implements InputRef<T> {
  /// Declares the input object [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  InputObjectDef(
    super.name,
    List<Arg<Object?>> Function() fieldsThunk,
    this.decode, {
    this.encode,
    this.isOneOf = false,
    super.description,
  }) : _fieldsThunk = fieldsThunk,
       typeRef = NonNullType(NamedType(Name(name)));

  final List<Arg<Object?>> Function() _fieldsThunk;

  /// The fields, as arguments in all but name.
  // Set on first read, so recursive input types can refer to each other
  // while their definitions are made.
  late final List<Arg<Object?>> fields = List.unmodifiable(_fieldsThunk());

  /// Builds [T] from the coerced field values.
  final T Function(Arguments values) decode;

  /// Writes a value as a JSON object; needed only to print a default value
  /// of this type.
  final JsonObject Function(T value)? encode;

  /// Whether this is a `@oneOf` input object.
  final bool isOneOf;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  InputRef<T?> get nullable => NullableInputRef(this);

  @override
  T adapt(Object? coerced) => coerced as T;

  @override
  JsonValue jsonOf(T value) {
    final write = encode;
    if (write == null) {
      throw StateError(
        'Input object "$name" has no encode function, so a default value of '
        'this type cannot be written.',
      );
    }
    return write(value);
  }
}
