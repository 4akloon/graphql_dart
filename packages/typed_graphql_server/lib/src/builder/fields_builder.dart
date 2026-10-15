import 'arg.dart';
import 'field_stub.dart';
import 'output_ref.dart';

/// The `t` of an object type's `fields` thunk: starts the field declarations.
///
/// {@category builder}
final class FieldsBuilder<P, C>() {
  /// Creates a builder; `ExecutableSchemaBuilder.object` does.
  this;

  /// Starts the field [name] of type [type]; finish it with `pure`,
  /// `resolve`, `resolveWith` or `declareOnly`.
  ///
  /// Two steps, so `R` is fixed by [type] before a resolver closure is
  /// inferred (spec 3.2).
  FieldStub<P, R, C> field<R>(
    String name,
    OutputRef<R> type, {
    List<Arg<Object?>> args = const [],
    String? description,
  }) => FieldStub(name, type, args: args, description: description);
}
