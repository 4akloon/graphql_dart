import 'dart:core';
import 'dart:core' as core;

import 'package:typed_graphql/typed_graphql.dart';

import 'scalar_type_def.dart';

/// The five built-in scalars of an `ExecutableSchemaBuilder`.
///
/// A member named `int` hides the type `int` in its class, which is why
/// these live in their own mixin and spell `core.int`. The scalars are not
/// declared types: the core's `BuiltIns` provides them.
mixin BuiltInScalarDefinitions {
  /// `Int`: a signed 32-bit integer.
  final ScalarTypeDef<core.int> int = ScalarTypeDef('Int', const IntCodec());

  /// `Float`: a double-precision number.
  final ScalarTypeDef<double> float = ScalarTypeDef(
    'Float',
    const FloatCodec(),
  );

  /// `String`: UTF-8 text.
  final ScalarTypeDef<String> string = ScalarTypeDef(
    'String',
    const StringCodec(),
  );

  /// `Boolean`: true or false.
  final ScalarTypeDef<bool> boolean = ScalarTypeDef(
    'Boolean',
    const BooleanCodec(),
  );

  /// `ID`: a unique identifier, held as a string.
  final ScalarTypeDef<String> id = ScalarTypeDef('ID', const IdCodec());
}
