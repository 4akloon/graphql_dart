# Operation Validation

A server validates an executable document against its schema before it runs
it (September2025, "Validation"). `DocumentValidator` checks a parsed
`Document` against a `ValidSchema` in one walk and returns a
`ValidDocument` or an `InvalidDocument` with every problem as a diagnostic;
an invalid document never throws.

## Rules

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
