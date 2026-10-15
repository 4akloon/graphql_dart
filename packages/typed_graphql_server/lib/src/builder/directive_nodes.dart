import 'package:typed_graphql/typed_graphql.dart';

/// The applied directives the builder writes for what a definition says:
/// deprecation, a scalar's specification URL and the one-of flag, in the
/// shape the core reads them back.
final class const DirectiveNodes() {
  /// Creates the factory.
  this;

  /// `@deprecated(reason: "...")`.
  AppliedDirective deprecated(String reason) =>
      AppliedDirective('deprecated', arguments: [_string('reason', reason)]);

  /// `@specifiedBy(url: "...")`.
  AppliedDirective specifiedBy(String url) =>
      AppliedDirective('specifiedBy', arguments: [_string('url', url)]);

  /// `@oneOf`.
  AppliedDirective oneOf() => AppliedDirective('oneOf');

  /// [directives] followed by `@deprecated` when [reason] is not null.
  List<AppliedDirective> withDeprecation(
    List<AppliedDirective> directives,
    String? reason,
  ) => [...directives, if (reason != null) deprecated(reason)];

  Argument _string(String name, String value) =>
      Argument(Name(name), StringValue(value));
}
