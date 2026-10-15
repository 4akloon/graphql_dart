import 'package:typed_graphql/typed_graphql.dart';

import 'field_resolver.dart';

/// Wraps the resolver [next] of a field that carries the applied [directive].
///
/// Registered by directive name in `BuildOptions.directiveMiddleware`.
///
/// {@category execution}
typedef DirectiveMiddleware<C> = FieldResolver<C> Function(
  FieldResolver<C> next,
  AppliedDirective directive,
);
