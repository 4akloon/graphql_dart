import 'package:typed_graphql/typed_graphql.dart';

import 'condition.dart';

/// Reads the `@include` and `@skip` directives of one selection.
final class DirectiveConditions {
  /// Creates the reader.
  const DirectiveConditions();

  /// The variable conditions of [directives], in directive order; null when
  /// a literal argument excludes the selection (`@include(if: false)`,
  /// `@skip(if: true)`). A literal that keeps the selection adds nothing.
  List<Condition>? of(List<Directive> directives) {
    final conditions = <Condition>[];
    for (final directive in directives) {
      final name = directive.name.value;
      if (name != 'include' && name != 'skip') {
        continue;
      }
      final isInclude = name == 'include';
      switch (_ifArgument(directive)) {
        case BooleanValue(:final value):
          if (value != isInclude) {
            return null;
          }
        case Variable(:final name):
          conditions.add(Condition(name.value, isInclude));
        case _:
          break;
      }
    }
    return conditions;
  }

  Value? _ifArgument(Directive directive) {
    for (final argument in directive.arguments) {
      if (argument.name.value == 'if') {
        return argument.value;
      }
    }
    return null;
  }
}
