import 'package:typed_graphql/typed_graphql.dart';

/// The rarer settings of an object type.
///
/// {@category builder}
final class ObjectOptions {
  /// Creates the options.
  const ObjectOptions({this.isTypeOf, this.directives = const []});

  /// Tells whether a value belongs to the type, when `value is P` is not
  /// enough (for example two types over one Dart class).
  final bool Function(Object? value)? isTypeOf;

  /// The directives applied to the type.
  final List<AppliedDirective> directives;
}
