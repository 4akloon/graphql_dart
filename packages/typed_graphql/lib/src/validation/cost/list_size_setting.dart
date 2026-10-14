import '../../language/ast/value.dart';
import '../../schema/model/applied_directive.dart';

/// The arguments of one applied `@listSize`, read once.
final class ListSizeSetting(
  /// The `assumedSize`, if any.
  final double? assumedSize,

  /// The names of the `slicingArguments`.
  final List<String> slicingArguments,

  /// The names of the `sizedFields`.
  final List<String> sizedFields,
) {
  /// Creates a setting.
  this;

  /// The setting of the first `@listSize` in [directives]; null when there
  /// is none. A malformed argument counts as absent: the schema check
  /// reports it.
  static ListSizeSetting? read(List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name == 'listSize') {
        return ListSizeSetting(
          switch (directive.argument('assumedSize')) {
            IntValue(:final value) => double.tryParse(value),
            _ => null,
          },
          _names(directive, 'slicingArguments'),
          _names(directive, 'sizedFields'),
        );
      }
    }
    return null;
  }

  static List<String> _names(AppliedDirective directive, String argument) {
    if (directive.argument(argument) case ListValue(:final values)) {
      return [
        for (final value in values)
          if (value case StringValue(:final value)) value,
      ];
    }
    return const [];
  }
}
