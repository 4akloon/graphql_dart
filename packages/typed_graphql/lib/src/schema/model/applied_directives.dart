import '../../language/ast/value.dart';
import 'applied_directive.dart';

/// What the built-in directives among the [directives] applied to one
/// schema element say: deprecation, a scalar's specification URL and the
/// one-of flag (spec §3.13).
///
/// The directives stay in the element's list, so printing is faithful;
/// these are typed views of them. An argument of the wrong kind reads as
/// absent: schema validation reports it.
final class const AppliedDirectives(
  /// The directives applied to the element, in the order written.
  final List<AppliedDirective> directives,
) {
  /// Creates the views.
  this;

  /// The reason `@deprecated` gives when it has no `reason` argument
  /// (spec §3.13, "@deprecated").
  static const String defaultDeprecationReason = 'No longer supported';

  /// The reason of the first `@deprecated`: its `reason` string, or
  /// [defaultDeprecationReason] without one; null when not deprecated.
  String? get deprecationReason {
    final directive = _named('deprecated');
    if (directive == null) {
      return null;
    }
    return switch (directive.argument('reason')) {
      StringValue(:final value) => value,
      _ => defaultDeprecationReason,
    };
  }

  /// The `url` string of the first `@specifiedBy`; null without one.
  String? get specifiedByUrl => switch (_named('specifiedBy')?.argument(
    'url',
  )) {
    StringValue(:final value) => value,
    _ => null,
  };

  /// Whether `@oneOf` is among the directives.
  bool get isOneOf => _named('oneOf') != null;

  AppliedDirective? _named(String name) {
    for (final directive in directives) {
      if (directive.name == name) {
        return directive;
      }
    }
    return null;
  }
}
