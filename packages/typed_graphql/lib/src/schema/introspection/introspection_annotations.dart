import '../../language/ast/argument.dart';
import '../../language/ast/name.dart';
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/applied_directives.dart';
import 'introspection_object.dart';

/// The applied directives that stand for what introspection reports as
/// fields: `@deprecated`, `@specifiedBy` and `@oneOf` (R2.1 keeps them as
/// directives, so the elements read them as SDL-built ones do).
final class const IntrospectionAnnotations() {
  /// Creates the annotations.
  this;

  /// `@deprecated` when [element] reports `isDeprecated` or a
  /// `deprecationReason`; without an argument for the default reason, as
  /// SDL writes it.
  List<AppliedDirective> deprecated(IntrospectionObject element) {
    final reason = element.optionalString('deprecationReason');
    if (reason == null && !element.flag('isDeprecated')) {
      return const [];
    }
    if (reason == null ||
        reason == AppliedDirectives.defaultDeprecationReason) {
      return [AppliedDirective('deprecated')];
    }
    return [_withString('deprecated', 'reason', reason)];
  }

  /// `@specifiedBy(url:)` when [type] reports a `specifiedByURL`.
  List<AppliedDirective> specifiedBy(IntrospectionObject type) => [
    if (type.optionalString('specifiedByURL') case final url?)
      _withString('specifiedBy', 'url', url),
  ];

  /// `@oneOf` when [type] reports `isOneOf`.
  List<AppliedDirective> oneOf(IntrospectionObject type) => [
    if (type.flag('isOneOf')) AppliedDirective('oneOf'),
  ];

  AppliedDirective _withString(String name, String argument, String text) =>
      AppliedDirective(
        name,
        arguments: [Argument(Name(argument), StringValue(text))],
      );
}
