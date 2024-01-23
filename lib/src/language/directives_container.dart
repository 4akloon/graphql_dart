import 'directive.dart';
import 'node.dart';

abstract mixin class DirectivesContainer<T extends DirectivesContainer<dynamic>>
    implements Node<T> {
  List<Directive> get directives;

  Map<String, List<Directive>> get directivesByName =>
      directives.fold<Map<String, List<Directive>>>(
        {},
        (Map<String, List<Directive>> acc, Directive directive) {
          final name = directive.name;
          final directives = acc[name] ?? [];
          directives.add(directive);
          return acc..[name] = directives;
        },
      );

  List<Directive> getDirectiveByName(String name) =>
      directivesByName[name] ?? [];

  bool hasDirectiveByName(String name) => directivesByName.containsKey(name);
}
