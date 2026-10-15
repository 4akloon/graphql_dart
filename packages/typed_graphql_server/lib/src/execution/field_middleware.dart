import 'field_resolver.dart';
import 'field_site.dart';

/// Wraps the resolver [next] of the field at [site] and returns the resolver
/// to run instead; returning [next] itself costs nothing at run time.
///
/// Composed once per field when the schema is built (spec 8).
///
/// {@category execution}
typedef FieldMiddleware<C> = FieldResolver<C> Function(
  FieldResolver<C> next,
  FieldSite site,
);
