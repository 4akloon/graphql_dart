# Language

The language layer reads and writes GraphQL text, the September2025 grammar,
and gives you the document as a typed syntax tree: a lexer, an error-resilient
parser, a printer that matches graphql-js to the character, visitors, a
transformer and schema coordinates.

## Parsing a document

`Parser().parse(source)` turns a `Source` into a `ParseResult`:

- `ParseSuccess(document)` when the text has no syntax error.
- `ParseFailure(partial, diagnostics)` when it has. After an error the parser
  skips to the next definition or selection and goes on, so one pass reports
  every error. `partial` holds the definitions that parsed completely; the tree
  never contains an error node.

Both carry `diagnostics`, in report order. `requireDocument()` gives the
document or throws a `GraphQLSyntaxException` with the diagnostics, which is
convenient in tests and scripts. A `Parser` is `const` and keeps no state.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  final source = Source(
    'query A { a(x: ) }\nquery B { b }',
    name: 'two.graphql',
  );

  switch (parser.parse(source)) {
    case ParseSuccess():
      print('no errors');
    case ParseFailure(:final partial, :final diagnostics):
      diagnostics.forEach(print);
      print('${partial.definitions.length} definition kept');
  }

  try {
    parser.parse(source).requireDocument();
  } on GraphQLSyntaxException catch (exception) {
    print('${exception.diagnostics.length} diagnostic');
  }
}
```

It prints:

```text
two.graphql:1:16: error GQL008: Unexpected ")".
1 definition kept
1 diagnostic
```

### Limits and the working draft

`ParserOptions` bound the work on untrusted text: `maxTokens` (15 000 by
default) and `maxDepth` (128), the nesting of selection sets, lists, objects
and list types. `null` removes a limit, which lets a hostile document exhaust memory
or the stack. The parser recurses on nested values, so a `maxDepth` near 1000
can overflow the stack on deeply nested object values; keep the default unless
you know the input.

Syntax from the specification's working draft is off by default.
`allowDirectiveExtensions` enables `extend directive`, directives on a
directive definition and the `DIRECTIVE_DEFINITION` location; without it each
is reported as `GQL014`. `allowEmptySelectionSets` enables `{ }`; without it
an empty selection set is reported as `GQL012`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const tiny = Parser(options: ParserOptions(maxTokens: 4));
  tiny.parse(Source('{ a b c d e }')).diagnostics.forEach(print);

  const shallow = Parser(options: ParserOptions(maxDepth: 2));
  shallow.parse(Source('{ a { b { c } } }')).diagnostics.forEach(print);

  final extension = Source('extend directive @tag @deprecated');
  const strict = Parser();
  const draft = Parser(options: ParserOptions(allowDirectiveExtensions: true));
  strict.parse(extension).diagnostics.forEach(print);
  print(draft.parse(extension).diagnostics);
}
```

It prints:

```text
GraphQL request:1:9: error GQL006: Document contains more than 4 tokens. Parsing aborted.
GraphQL request:1:9: error GQL010: Document nests deeper than 2 levels.
GraphQL request:1:1: error GQL014: Directive extensions are a working-draft feature; enable them with ParserOptions.allowDirectiveExtensions.
[]
```

## The syntax tree

Every node extends `Node`. A node is immutable and has:

- `start` and `end`, the offsets in the source it was read from (0 for a node
  built in code);
- `children`, in the order of graphql-js's `QueryDocumentKeys`;
- `withChildren(list)`, a copy with other children, which `AstTransformer` uses;
- `isEquivalentTo(other)`, which compares structure and ignores positions.
  Nodes do not override `==`.

The kinds of node are sealed families, so a `switch` over one is checked by the
compiler:

| Family | Members |
|---|---|
| `Definition` (not sealed) | `OperationDefinition`, `FragmentDefinition`, the type-system definitions and extensions |
| `Selection` | `Field`, `FragmentSpread`, `InlineFragment` |
| `Value` | `Variable`, `IntValue`, `FloatValue`, `StringValue`, `BooleanValue`, `NullValue`, `EnumValue`, `ListValue`, `ObjectValue` |
| `TypeRef` | `NamedType`, `ListType`, `NonNullType` |
| `SchemaCoordinate` | `TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`, `DirectiveCoordinate`, `DirectiveArgumentCoordinate` |

`Definition` is not sealed, because the working draft adds definitions: a
`switch` statement over it needs no `default`, and one would hide kinds added
later, so name the cases you handle.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
query Hero(\$id: ID!) {
  hero(id: \$id) { name ...Details }
}

fragment Details on Character { appearsIn }
''');
  final document = const Parser().parse(source).requireDocument();

  for (final definition in document.definitions) {
    switch (definition) {
      case OperationDefinition(:final operation, :final name):
        print('${operation.name} ${name?.value}');
      case FragmentDefinition(:final name, :final typeCondition):
        print('fragment ${name.value} on ${typeCondition.name.value}');
      case _:
        print('another kind of definition');
    }
  }

  // Every node knows where it was read from.
  final operation = document.definitions.first as OperationDefinition;
  final hero = operation.selectionSet.selections.single as Field;
  print(source.body.substring(hero.start, hero.end));
  print(hero.children.length);

  // Structure, without positions.
  final other = const Parser()
      .parse(Source('query Hero(\$id:ID!){hero(id:\$id){name ...Details}}'))
      .requireDocument();
  print(operation.isEquivalentTo(other.definitions.first));
}
```

It prints:

```text
query Hero
fragment Details on Character
hero(id: $id) { name ...Details }
3
true
```

### Single values and types

`parseValue(source, isConst:)` and `parseTypeRef(source)` parse one element and
return a `ParseElementResult`: `ParseElementSuccess(value)` or
`ParseElementFailure`. There is no partial element. With `isConst`, a variable
is an error (`GQL009`), as in a default value.

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(TypeRef type) => switch (type) {
  NamedType(:final name) => name.value,
  ListType(:final type) => 'list of ${describe(type)}',
  NonNullType(:final type) => 'non-null (${describe(type)})',
};

void main() {
  const parser = Parser();

  final value = parser.parseValue(Source('[1, {a: "x"}, ENUM]'));
  if (value case ParseElementSuccess(:final value)) {
    print(const Printer(isMinified: true).print(value));
  }

  // A variable is not a constant value.
  final variable = parser.parseValue(Source(r'[$id]'), isConst: true);
  print(variable.diagnostics.single);

  final type = parser.parseTypeRef(Source('[String!]!'));
  if (type case ParseElementSuccess(:final value)) {
    print(describe(value));
  }
}
```

It prints:

```text
[1{a:"x"}ENUM]
GraphQL request:1:2: error GQL009: Unexpected variable "$id" in constant value.
non-null (list of non-null (String))
```

## Printing

`Printer` prints any node, a whole document or a single selection, as GraphQL
text. The default is canonical: character for character what graphql-js's
`print` gives, with lines wrapped at 80 columns. `Printer(isMinified: true)`
drops every character that does not matter, for the wire and for persisted
query hashes: a space only between two tokens that are not punctuators, or
before `...`, and block strings in their shortest form. Parsing the output of either
form gives a tree that `isEquivalentTo` the original.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  final source = Source(
    r'query Hero($id:ID!,$withFriends:Boolean=false){hero(id:$id){name '
    r'friends @include(if:$withFriends){name}...on Droid{primaryFunction}}}',
  );
  final document = parser.parse(source).requireDocument();

  print(const Printer().print(document));
  print(const Printer(isMinified: true).print(document));

  final again = parser
      .parse(Source(const Printer(isMinified: true).print(document)))
      .requireDocument();
  print(document.isEquivalentTo(again));

  // Any node prints, not only a document.
  final operation = document.definitions.single as OperationDefinition;
  print(const Printer().print(operation.selectionSet.selections.single));
}
```

It prints:

```text
query Hero($id: ID!, $withFriends: Boolean = false) {
  hero(id: $id) {
    name
    friends @include(if: $withFriends) {
      name
    }
    ... on Droid {
      primaryFunction
    }
  }
}
query Hero($id:ID!$withFriends:Boolean=false){hero(id:$id){name friends@include(if:$withFriends){name}...on Droid{primaryFunction}}}
true
hero(id: $id) {
  name
  friends @include(if: $withFriends) {
    name
  }
  ... on Droid {
    primaryFunction
  }
}
```

Printing recurses over the tree, so it is bounded by the parser's `maxDepth`; a
tree built in code that is deeper can overflow the stack.

## Visiting

`AstWalker().walk(root, visitor)` walks a tree depth-first through `children`
and calls an `AstVisitor` on the way down (`enter`) and on the way up
(`leave`). Both do nothing by default, so a visitor overrides only what it
needs. `enter` returns a `VisitAction`:

- `next` goes into the node's children, and `leave` is called afterwards;
- `skip` passes over the children, and the node is not left either;
- `stop` ends the walk: nothing else is entered or left.

The walker keeps its own stack instead of recursing, so a tree of any depth is
safe on the web too. `ParallelVisitor` runs several visitors in one walk, each
called as if it walked alone, as graphql-js's `visitInParallel` does. It keeps
the skip and stop state of each visitor, so use a new one for every walk.

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Counts the fields of a document, leaving fragment definitions alone.
final class FieldCounter extends AstVisitor {
  int count = 0;

  @override
  VisitAction enter(Node node) => switch (node) {
    FragmentDefinition() => VisitAction.skip,
    Field() => _count(),
    _ => VisitAction.next,
  };

  VisitAction _count() {
    count++;
    return VisitAction.next;
  }
}

/// Collects the names of the variables a document uses.
final class VariableCollector extends AstVisitor {
  final Set<String> names = {};

  @override
  VisitAction enter(Node node) {
    if (node is Variable) names.add(node.name.value);
    return VisitAction.next;
  }
}

/// Stops the walk at the first field with the given name.
final class FieldFinder extends AstVisitor {
  FieldFinder(this.name);

  final String name;
  Field? found;

  @override
  VisitAction enter(Node node) {
    if (node is Field && node.name.value == name) {
      found = node;
      return VisitAction.stop;
    }
    return VisitAction.next;
  }
}

void main() {
  final source = Source(r'''
query Hero($id: ID!) { hero(id: $id) { name ...Details } }
fragment Details on Character { appearsIn friends { name } }
''');
  final document = const Parser().parse(source).requireDocument();
  const walker = AstWalker();

  final counter = FieldCounter();
  walker.walk(document, counter);
  print('fields outside fragments: ${counter.count}');

  // Two visitors, one walk.
  final other = FieldCounter();
  final variables = VariableCollector();
  walker.walk(document, ParallelVisitor([other, variables]));
  print('${other.count} fields, variables ${variables.names}');

  final finder = FieldFinder('friends');
  walker.walk(document, finder);
  if (finder.found case final field?) {
    print('friends at ${source.locationOf(field.start)}');
  }
}
```

It prints:

```text
fields outside fragments: 2
2 fields, variables {id}
friends at 2:43
```

## Transforming

`AstTransformer.transform(root)` rebuilds a tree bottom-up. `rewrite(node)`
sees each node after its children were rewritten and returns what takes its
place: the node itself to keep it, another node to replace it, or `null` to
remove it from its parent. The parent is rebuilt with `withChildren`, so it
decides what it accepts: removing a child it requires, such as the name of a
`Field`, is a `StateError`.

The original tree is never changed, and a branch where nothing changed keeps
its instance, so `identical` tells whether a transform changed anything. Like
the walker, it keeps its own stack instead of recursing.

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Adds `__typename` to every selection set that lacks it.
final class AddTypename extends AstTransformer {
  const AddTypename();

  @override
  Node? rewrite(Node node) => switch (node) {
    SelectionSet(:final selections) when !selections.any(_isTypename) =>
      SelectionSet([...selections, Field(null, const Name('__typename'))]),
    _ => node,
  };

  static bool _isTypename(Selection selection) =>
      selection is Field && selection.name.value == '__typename';
}

/// Removes the directives with the given name wherever they are applied.
final class StripDirective extends AstTransformer {
  const StripDirective(this.name);

  final String name;

  @override
  Node? rewrite(Node node) =>
      node is Directive && node.name.value == name ? null : node;
}

/// Tries to remove the name of the field `hero`, which a field requires.
final class RemoveHeroName extends AstTransformer {
  const RemoveHeroName();

  @override
  Node? rewrite(Node node) =>
      node is Name && node.value == 'hero' ? null : node;
}

void main() {
  const printer = Printer(isMinified: true);
  final document = const Parser()
      .parse(Source('query Q @client { hero @client { name } }'))
      .requireDocument();

  print(printer.print(const AddTypename().transform(document)!));
  print(printer.print(const StripDirective('client').transform(document)!));

  // The original is untouched, and an unchanged tree is the same instance.
  print(printer.print(document));
  print(identical(const StripDirective('other').transform(document), document));

  try {
    const RemoveHeroName().transform(document);
  } on StateError {
    print('a field needs its name');
  }
}
```

It prints:

```text
query Q@client{hero@client{name __typename}__typename}
query Q{hero{name}}
query Q@client{hero@client{name}}
true
a field needs its name
```

## Schema coordinates

A schema coordinate names one element of a schema in a single line, such as
`Query.hero(episode:)` (September2025, "Schema Coordinates").
`Parser().parseSchemaCoordinate(source)` returns a
`ParseElementResult<SchemaCoordinate>`. A coordinate holds no ignored tokens, so
white space is an error. `ParserOptions` do not apply to it.

| Text | Node |
|---|---|
| `Query` | `TypeCoordinate` |
| `Query.hero` | `MemberCoordinate`: a field, input field or enum value |
| `Query.hero(episode:)` | `ArgumentCoordinate` |
| `@skip` | `DirectiveCoordinate` |
| `@skip(if:)` | `DirectiveArgumentCoordinate` |

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(SchemaCoordinate coordinate) => switch (coordinate) {
  TypeCoordinate(:final name) => 'the type ${name.value}',
  MemberCoordinate(:final name, :final memberName) =>
    'the member ${memberName.value} of ${name.value}',
  ArgumentCoordinate(:final name, :final fieldName, :final argumentName) =>
    'the argument ${argumentName.value} of ${name.value}.${fieldName.value}',
  DirectiveCoordinate(:final name) => 'the directive @${name.value}',
  DirectiveArgumentCoordinate(:final name, :final argumentName) =>
    'the argument ${argumentName.value} of @${name.value}',
};

void main() {
  const parser = Parser();
  const texts = ['Query', 'Query.hero', 'Query.hero(episode:)', '@skip(if:)'];
  for (final text in texts) {
    final result = parser.parseSchemaCoordinate(Source(text));
    if (result case ParseElementSuccess(:final value)) {
      print('$text is ${describe(value)}');
    }
  }

  final spaced = parser.parseSchemaCoordinate(Source('Query. hero'));
  print(spaced.diagnostics.single);
}
```

It prints:

```text
Query is the type Query
Query.hero is the member hero of Query
Query.hero(episode:) is the argument episode of Query.hero
@skip(if:) is the argument if of @skip
GraphQL request:1:7: error GQL001: Invalid character: " ".
```

## Tokens

`Lexer(source, sink).advance()` returns the next `Token`: a `TokenKind`, the
`start` and `end` offsets and, for names, numbers and strings, the `value`.
Ignored tokens (white space, commas, comments) are skipped; `keepComments`
returns the comments too. The lexer never throws: text that is no token becomes
one `TokenKind.error` token over the offending run and one diagnostic in the
sink. `maxTokens` stops it with `GQL006`. The parser reads tokens through this
class, so you need it only for tooling that works on tokens.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final lexer = Lexer(Source('{ hero(id: 1) } # done'), DiagnosticSink());
  for (
    var token = lexer.advance();
    token.kind != TokenKind.eof;
    token = lexer.advance()
  ) {
    print(token);
  }
}
```

It prints:

```text
"{"@0:1
Name "hero"@2:6
"("@6:7
Name "id"@7:9
":"@9:10
Int "1"@11:12
")"@12:13
"}"@14:15
```
