# Authorization

A field can carry an `Authorization` rule: `Authorization.requires(['admin'])`
names what the caller needs, `Authorization.public()` says anyone may read it.
The rule is data. An `Authorizer<C>`, given to `build` in
`BuildOptions.authorizer`, decides what the requirements mean and answers
`Allow` or `Deny`, now or later.

A rule is set on a field with `.withAuthorization(...)`, or on every field of
an object type with `ObjectOptions.authorization`; a field's own rule wins
over its type's. The authorizer runs for a guarded field after its arguments
are coerced and before its middleware, for pure getters too, and never for a
`public` or an introspection field. A schema with a guarded field and no
authorizer does not build (`GQL304`).

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Roles implements Authorizer<Set<String>> {
  @override
  FutureOr<AuthorizationDecision> authorize(FieldAccess<Set<String>> access) =>
      access.requirements.every(access.context.contains)
      ? const Allow()
      : const Deny();
}

void main() {
  final b = ExecutableSchemaBuilder<Set<String>>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string).pure((_) => 'hello'),
      t
          .field('secret', b.string.nullable)
          .withAuthorization(Authorization.requires(['admin']))
          .pure((_) => 'the secret'),
    ],
  );
  final schema = b.build(
    query: query,
    options: BuildOptions<Set<String>>(authorizer: Roles()),
  );
  final document = const Parser()
      .parse(Source('{ hello secret }'))
      .requireDocument();
  for (final roles in [
    <String>{'admin'},
    <String>{},
  ]) {
    final result = schema.execute(
      ValidDocument.assumeValid(schema.schema, document),
      context: roles,
    );
    print(jsonEncode((result as ExecutionResult).toJson().toJson()));
  }
}
```

It prints:

```text
{"data":{"hello":"hello","secret":"the secret"}}
{"errors":[{"message":"Not authorized to access Query.secret.","path":["secret"],"extensions":{"code":"GQL352"}}],"data":{"hello":"hello","secret":null}}
```

A deny is a field error with the code `GQL352` and the message
`Not authorized to access Type.field.`, or the message given to `Deny`; null
propagates as for any field error. An exception thrown by the authorizer is
masked like a resolver's and reaches `ExecutionOptions.onError`.

`SelectedField.authorization` tells a look-ahead which rule applies to a field.
`AuthorizationCoverage(schema).uncovered` lists the fields with no rule on the
field or its type, introspection excluded, sorted; assert it is empty in an
application's tests so a new field cannot ship unguarded.
