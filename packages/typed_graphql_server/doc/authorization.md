# Authorization

The builder does not decide who may read a field; it gives every field a place
to say what it needs and calls one hook to check it. A field can carry an `Authorization` rule: `Authorization.requires(['admin'])`
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
propagates as for any field error, so guard a field that may be absent with a
nullable type. An exception thrown by the authorizer is masked like a
resolver's and reaches `ExecutionOptions.onError`. A denied field never runs
its resolver or its middleware.

## Type rules, field rules and public fields

A rule on an object type (`ObjectOptions.authorization`) covers every field of
the type that has none of its own. A field's own rule replaces it, and
`Authorization.public()` opts a field out of the type's rule: the authorizer is
not asked. Introspection fields are never guarded.

A rule on an interface field guards the implementations that inherit the field.
An object that redeclares the field does not inherit the interface's rule: give
it its own, or its type's.

## Asynchronous decisions and deny messages

`authorize` returns a `FutureOr`, so an authorizer may look the answer up in a
database or a token service; a synchronous answer costs no `Future`. `Deny`
takes an optional message for the client; keep it free of details an attacker
could use.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Lookup implements Authorizer<Set<String>> {
  @override
  FutureOr<AuthorizationDecision> authorize(
    FieldAccess<Set<String>> access,
  ) async {
    await Future<void>.delayed(Duration.zero);
    final missing = access.requirements.where(
      (role) => !access.context.contains(role),
    );
    return missing.isEmpty
        ? const Allow()
        : Deny(message: 'Missing role: ${missing.join(', ')}.');
  }
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Set<String>>();
  final account = b.object<Object?>(
    'Account',
    fields: (t) => [
      t
          .field('id', b.string)
          .withAuthorization(Authorization.public())
          .pure((_) => 'a-1'),
      t.field('balance', b.int.nullable).pure((_) => 120),
      t
          .field('audit', b.string.nullable)
          .withAuthorization(Authorization.requires(['admin']))
          .pure((_) => 'clean'),
    ],
    options: ObjectOptions(authorization: Authorization.requires(['owner'])),
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('account', account).pure((_) => const Object())],
  );
  final schema = b.build(
    query: query,
    options: BuildOptions<Set<String>>(authorizer: Lookup()),
  );
  print(AuthorizationCoverage(schema).uncovered);

  final document = const Parser()
      .parse(Source('{ account { id balance audit } }'))
      .requireDocument();
  final result = await schema.execute(
    ValidDocument.assumeValid(schema.schema, document),
    context: {'owner'},
  );
  print(jsonEncode((result as ExecutionResult).toJson().toJson()));
}
```

It prints:

```text
[Query.account]
{"errors":[{"message":"Missing role: admin.","path":["account","audit"],"extensions":{"code":"GQL352"}}],"data":{"account":{"id":"a-1","balance":120,"audit":null}}}
```

`id` is public, `balance` takes the type's rule `owner`, and `audit` its own
rule `admin`. `SelectedField.authorization` gives a look-ahead the rule that
applies to a field, so a resolver can skip loading what the caller may not
read.

## Checking coverage in a test

`AuthorizationCoverage(schema).uncovered` lists, sorted, the coordinates
(`Type.field`) of the fields that have no rule on the field or on its type.
`public` counts as a rule: the decision is explicit. Introspection fields are
excluded. The program above prints `Query.account`, the root field nobody
guarded. Assert that the list is empty in the application's tests, with the
public entry points marked `public`, so that a new field cannot ship without
a decision:

```text
test('every field has an authorization rule', () {
  expect(AuthorizationCoverage(schema).uncovered, isEmpty);
});
```

## A rule without an authorizer

A rule is data until an authorizer reads it. A build with a field that needs
the authorizer (`Authorization.requires`) and no `BuildOptions.authorizer`
fails with one `GQL304` diagnostic that lists every such field, so a missing
hook is never a silently open schema. A `public` rule needs no authorizer.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('a', b.string)
          .withAuthorization(Authorization.requires(['x']))
          .pure((_) => 'a'),
      t
          .field('b', b.string)
          .withAuthorization(Authorization.requires(['y']))
          .pure((_) => 'b'),
    ],
  );
  try {
    b.build(query: query);
  } on SchemaBuildError catch (error) {
    print(error.diagnostics.length);
    print(error.diagnostics.single.message);
  }
}
```

It prints:

```text
1
Fields are guarded by an authorization rule but the build has no authorizer (BuildOptions.authorizer): Query.a, Query.b.
```
