import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'arguments.dart';
import 'built_in_scalar_definitions.dart';
import 'definition_registry.dart';
import 'enum_type_def.dart';
import 'enum_value_mapping.dart';
import 'input_list_ref.dart';
import 'input_object_def.dart';
import 'input_ref.dart';
import 'named_type_def.dart';
import 'output_list_ref.dart';
import 'output_ref.dart';
import 'scalar_type_def.dart';

/// Declares the types of a schema in typed Dart code; `C` is the context
/// type every resolver receives (R4.1).
///
/// Every definition made through a builder is part of the schema it builds,
/// in creation order. The core already exports `SchemaBuilder` (SDL to
/// schema), hence the name.
///
/// {@category builder}
final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
  /// Creates a builder with no definitions.
  this;

  final DefinitionRegistry _registry = DefinitionRegistry();

  /// The definitions made so far, in creation order.
  List<NamedTypeDef> get definitions => _registry.snapshot;

  /// Declares the custom scalar [name] over [codec].
  ScalarTypeDef<T> scalar<T extends Object>(
    String name,
    ScalarCodec<T> codec, {
    String? description,
    String? specifiedByUrl,
  }) => _registry.add(
    ScalarTypeDef(
      name,
      codec,
      description: description,
      specifiedByUrl: specifiedByUrl,
    ),
  );

  /// Declares the enum [name] over the Dart enum [values].
  ///
  /// [mapping] gives the names, descriptions and deprecations of the values
  /// (a value's name defaults to [Enum.name]); the parameters of the three
  /// callbacks are grouped in one object to keep the signature short.
  EnumTypeDef<E> enumType<E extends Enum>(
    String name,
    List<E> values, {
    EnumValueMapping<E>? mapping,
    String? description,
  }) {
    final effective = mapping ?? EnumValueMapping<E>();
    return _registry.add(
      EnumTypeDef(name, [
        for (final value in values) effective.define(value),
      ], description: description),
    );
  }

  /// The non-null list of [item] as an output type.
  OutputRef<Iterable<R>> list<R>(OutputRef<R> item) => OutputListRef(item);

  /// The non-null list of [item] as an input type.
  InputRef<List<T>> inputList<T>(InputRef<T> item) => InputListRef(item);

  /// Declares the input object [name] decoded to [T].
  ///
  /// [fields] runs once, on first use. [decode] builds [T] from the coerced
  /// values; [encode] is needed only when a default value of this type is
  /// declared.
  InputObjectDef<T> inputObject<T extends Object>(
    String name, {
    required List<Arg<Object?>> Function() fields,
    required T Function(Arguments values) decode,
    JsonObject Function(T value)? encode,
    String? description,
  }) => _registry.add(
    InputObjectDef(
      name,
      fields,
      decode,
      encode: encode,
      description: description,
    ),
  );

  /// Declares the `@oneOf` input object [name]: exactly one of its fields is
  /// given. The parameters are those of [inputObject]; this is a separate
  /// method to keep each signature within five parameters.
  InputObjectDef<T> oneOfInputObject<T extends Object>(
    String name, {
    required List<Arg<Object?>> Function() fields,
    required T Function(Arguments values) decode,
    JsonObject Function(T value)? encode,
    String? description,
  }) => _registry.add(
    InputObjectDef(
      name,
      fields,
      decode,
      encode: encode,
      isOneOf: true,
      description: description,
    ),
  );
}
