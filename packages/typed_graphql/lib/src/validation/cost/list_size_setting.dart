import 'dart:math';

import '../../language/ast/value.dart';
import '../../schema/model/applied_directive.dart';
import '../../schema/model/string_list_argument.dart';

/// The arguments of one applied `@listSize`, read once.
final class ListSizeSetting(
  /// The `assumedSize`, if any.
  final double? assumedSize,

  /// The names of the `slicingArguments`.
  final List<String> slicingArguments,

  /// The names of the `sizedFields`.
  final List<String> sizedFields,

  /// Whether a field must be given exactly one slicing argument (the
  /// draft's `requireOneSlicingArgument`, true by default).
  final bool requiresOneSlicingArgument,
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
            // Negative sizes count as 0 and huge ones stay finite.
            IntValue(:final value) => switch (double.tryParse(value)) {
              final size? => min<double>(
                double.maxFinite,
                max<double>(0, size),
              ),
              null => null,
            },
            _ => null,
          },
          StringListArgument(directive).named('slicingArguments'),
          StringListArgument(directive).named('sizedFields'),
          switch (directive.argument('requireOneSlicingArgument')) {
            BooleanValue(value: false) => false,
            _ => true,
          },
        );
      }
    }
    return null;
  }
}
