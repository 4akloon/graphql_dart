# Operation Validation

A server validates an executable document against its schema before it runs
it (September2025, "Validation"). `DocumentValidator` checks a parsed
`Document` against a `ValidSchema` in one walk and returns a
`ValidDocument` or an `InvalidDocument` with every problem as a diagnostic;
an invalid document never throws.

## Validating a document

By default the validator runs `DocumentValidator.specifiedRules`, the 30
rules of the specification. Each problem is a diagnostic with a stable code
and graphql-js's message, at the place it is about when the validator is
given the `Source`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final schema = switch (const SchemaBuilder().fromSdl(
    const Parser()
        .parse(Source('type Query { name: String friends: [Query] }'))
        .requireDocument(),
  )) {
    BuildSuccess(:final schema) => schema,
    BuildFailure() => throw StateError('the schema is valid'),
  };
  final valid = switch (const SchemaValidator().validate(schema)) {
    final ValidSchema valid => valid,
    InvalidSchema() => throw StateError('the schema is valid'),
  };
  final source = Source(r'query ($id: ID) { nam friends }');
  final document = const Parser().parse(source).requireDocument();
  const validator = DocumentValidator();
  switch (validator.validate(valid, document, source: source)) {
    case ValidDocument():
      print('valid');
    case InvalidDocument(:final diagnostics):
      for (final diagnostic in diagnostics) {
        final location = diagnostic.span?.location;
        print('$location ${diagnostic.code.id} ${diagnostic.message}');
      }
  }
}
```

It prints:

```text
1:19 GQL205 Cannot query field "nam" on type "Query". Did you mean "name"?
1:23 GQL207 Field "friends" of type "[Query]" must have a selection of subfields. Did you mean "friends { ... }"?
1:8 GQL228 Variable "$id" is never used.
```

The rules that need an operation's fragments, such as `GQL228`, report
when the walk has left the document, after the others. "Did you mean"
suggestions follow graphql-js; a production server turns them
off with `includesSuggestions: false`, so that error messages do not list
the schema's names.

## The specified rules

The rules are public classes, so a list can drop, reorder or extend them:
`DocumentValidator(rules: [...DocumentValidator.specifiedRules, MyRule()])`.
Three graphql-js rules are split so that each class checks one rule of the
specification and reports one code.

| Code | Rule | Specification |
|---|---|---|
| `GQL200` | `ExecutableDefinitionsRule` | §5.1.1 Executable Definitions |
| `GQL201` | `KnownOperationTypesRule` | §5.2.1.1 Operation Type Existence |
| `GQL202` | `UniqueOperationNamesRule` | §5.2.2.1 Operation Name Uniqueness |
| `GQL203` | `LoneAnonymousOperationRule` | §5.2.3.1 Lone Anonymous Operation |
| `GQL204` | `SingleFieldSubscriptionsRule` | §5.2.4.1 Single Root Field |
| `GQL205` | `FieldsOnCorrectTypeRule` | §5.3.1 Field Selections |
| `GQL206` | `OverlappingFieldsCanBeMergedRule` | §5.3.2 Field Selection Merging |
| `GQL207` | `ScalarLeafsRule` | §5.3.3 Leaf Field Selections |
| `GQL208` | `KnownArgumentNamesRule` | §5.4.1 Argument Names |
| `GQL209` | `UniqueArgumentNamesRule` | §5.4.2 Argument Uniqueness |
| `GQL210` | `ProvidedRequiredArgumentsRule` | §5.4.3 Required Arguments |
| `GQL211` | `UniqueFragmentNamesRule` | §5.5.1.1 Fragment Name Uniqueness |
| `GQL212` | `KnownTypeNamesRule` | §5.5.1.2 Fragment Spread Type Existence |
| `GQL213` | `FragmentsOnCompositeTypesRule` | §5.5.1.3 Fragments on Object, Interface or Union Types |
| `GQL214` | `NoUnusedFragmentsRule` | §5.5.1.4 Fragments Must Be Used |
| `GQL215` | `KnownFragmentNamesRule` | §5.5.2.1 Fragment Spread Target Defined |
| `GQL216` | `NoFragmentCyclesRule` | §5.5.2.2 Fragment Spreads Must Not Form Cycles |
| `GQL217` | `PossibleFragmentSpreadsRule` | §5.5.2.3 Fragment Spread Is Possible |
| `GQL218` | `ValuesOfCorrectTypeRule` | §5.6.1 Values of Correct Type |
| `GQL219` | `InputObjectFieldNamesRule` | §5.6.2 Input Object Field Names |
| `GQL220` | `UniqueInputFieldNamesRule` | §5.6.3 Input Object Field Uniqueness |
| `GQL221` | `InputObjectRequiredFieldsRule` | §5.6.4 Input Object Required Fields |
| `GQL222` | `KnownDirectivesRule` | §5.7.1 Directives Are Defined |
| `GQL223` | `DirectivesInValidLocationsRule` | §5.7.2 Directives Are in Valid Locations |
| `GQL224` | `UniqueDirectivesPerLocationRule` | §5.7.3 Directives Are Unique per Location |
| `GQL225` | `UniqueVariableNamesRule` | §5.8.1 Variable Uniqueness |
| `GQL226` | `VariablesAreInputTypesRule` | §5.8.2 Variables Are Input Types |
| `GQL227` | `NoUndefinedVariablesRule` | §5.8.3 All Variable Uses Defined |
| `GQL228` | `NoUnusedVariablesRule` | §5.8.4 All Variables Used |
| `GQL229` | `VariablesInAllowedPositionRule` | §5.8.5 All Variable Usages Are Allowed |

`KnownTypeNamesRule` also checks the types of variable definitions, as
graphql-js does. Descriptions on operations and variables are not
validated (§2.2).

## Field selection merging

Two fields with one response name must select the same thing. graphql-js
compares every pair of such fields, which is quadratic: a document with a
few thousand copies of one field keeps it busy for seconds.
`OverlappingFieldsCanBeMergedRule` merges the fields level by level instead
and compares each field with the first field of every other kind, so its
work grows with the size of the document. It reports graphql-js's messages
at graphql-js's places; with three or more conflicting fields of one name
it may report fewer conflicts, since one report per kind is enough to show
the problem.

## Custom rules

A `ValidationRule` is one check. For each run the validator asks every rule
for a fresh `AstVisitor` and walks the document once with all of them. At
each node a visitor reads the types around it from
`ValidationContext.typeInfo` (`TypeInfo`: the parent type, the field
definition, the expected input type) and reports with
`ValidationContext.report`, which points the diagnostic at the first node
it is given. A custom rule reports `GQL231` or a code of its own choice.

```dart
import 'package:typed_graphql/typed_graphql.dart';

final class NoSecretsRule extends ValidationRule {
  const NoSecretsRule();

  @override
  AstVisitor createVisitor(ValidationContext context) => _NoSecrets(context);
}

final class _NoSecrets extends AstVisitor {
  _NoSecrets(this.context);

  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    if (node is Field && context.typeInfo.fieldDefinition?.name == 'secret') {
      context.report(.customRuleViolation, 'Secrets are not served.', [node]);
    }
    return .next;
  }
}

void main() {
  final schema = switch (const SchemaBuilder().fromSdl(
    const Parser()
        .parse(Source('type Query { name: String secret: String }'))
        .requireDocument(),
  )) {
    BuildSuccess(:final schema) => schema,
    BuildFailure() => throw StateError('the schema is valid'),
  };
  final valid = switch (const SchemaValidator().validate(schema)) {
    final ValidSchema valid => valid,
    InvalidSchema() => throw StateError('the schema is valid'),
  };
  final source = Source('{ name secret }');
  final document = const Parser().parse(source).requireDocument();
  const validator = DocumentValidator(rules: [NoSecretsRule()]);
  switch (validator.validate(valid, document, source: source)) {
    case ValidDocument():
      print('valid');
    case InvalidDocument(:final diagnostics):
      for (final diagnostic in diagnostics) {
        print('${diagnostic.span?.location} ${diagnostic.message}');
      }
  }
}
```

It prints:

```text
1:8 Secrets are not served.
```

## Work limits

Some checks do more work than one walk: the fragments an operation reaches,
the fields that must merge. The run charges that work to a budget
(`maxSteps`, a million by default); a document shaped to exceed it gets
one `GQL230` error instead of keeping the server busy. `maxErrors` stops
the run after that many errors with one `GQL000`.
