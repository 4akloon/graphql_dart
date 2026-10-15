import 'dart:async';

import '../builder/arguments.dart';
import 'field_info.dart';

/// The function that produces a field's value: the parent, the coerced
/// arguments, the context and what is known about the field.
///
/// This is the shape of a resolver as the middleware chain sees it
/// (spec 8).
///
/// {@category execution}
typedef FieldResolver<C> = FutureOr<Object?> Function(
  Object? parent,
  Arguments args,
  C context,
  FieldInfo info,
);
