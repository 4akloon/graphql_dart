import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/operation_text.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

const _schema = '''
interface Root { id: ID! }
type User { id: ID! name: String }
type Query implements Root {
  id: ID!
  user: User
  users: [User!]!
}
type Subscription implements Root {
  id: ID!
  user: User
}
''';

void main() {
  String textOf(String schema, String document, [String? operationName]) {
    final fixture = PlanFixture(schema, document);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere(
          (operation) =>
              operationName == null || operation.name?.value == operationName,
        );
    return OperationText(fixture.schema, fixture.fragments).of(operation);
  }

  test('GetUser: fields get __typename, the fragment does not', () {
    expect(
      textOf(operationSchema, operationDocument, 'GetUser'),
      r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){'
      r'user(id:$id){...UserCard@include(if:$full)role createdAt cursor '
      r'friends(first:2)@include(if:$withFriends){id name __typename}'
      '__typename}}fragment UserCard on User{id name}',
    );
  });

  test('FindNode: the abstract field has __typename, inline fragments not', () {
    expect(
      textOf(operationSchema, operationDocument, 'FindNode'),
      r'query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}'
      '...on Bot{model}__typename}}fragment UserCard on User{id name}',
    );
  });

  test('fragments are sorted by name and written once', () {
    expect(
      textOf(_schema, '''
query { user { ...Zeta ...Mid } }
fragment Zeta on User { ...Alpha ...Mid }
fragment Mid on User { name ...Alpha }
fragment Alpha on User { id }
'''),
      '{user{...Zeta ...Mid __typename}}'
      'fragment Alpha on User{id}'
      'fragment Mid on User{name ...Alpha}'
      'fragment Zeta on User{...Alpha ...Mid}',
    );
  });

  test('a fragment another operation spreads is not part of the text', () {
    expect(
      textOf(_schema, '''
query A { user { ...X } }
query B { user { ...Y } }
fragment X on User { id }
fragment Y on User { name }
''', 'A'),
      'query A{user{...X __typename}}fragment X on User{id}',
    );
  });

  test('a chain of 500 fragments does not overflow the stack', () {
    final document = StringBuffer('query { user { ...F0 } }\n');
    for (var index = 0; index < 499; index++) {
      document.writeln('fragment F$index on User { ...F${index + 1} }');
    }
    document.writeln('fragment F499 on User { id }');
    final String text = textOf(_schema, document.toString());
    expect(RegExp('fragment ').allMatches(text), hasLength(500));
    expect(text, endsWith('fragment F99 on User{...F100}'));
  });

  test('an existing unaliased __typename is not repeated', () {
    expect(
      textOf(_schema, 'query { user { __typename id } }'),
      '{user{__typename id}}',
    );
  });

  test('an aliased __typename does not count', () {
    expect(
      textOf(_schema, 'query { user { kind: __typename id } }'),
      '{user{kind:__typename id __typename}}',
    );
  });

  test('a fragment on an abstract type at the root adds __typename', () {
    expect(
      textOf(_schema, '''
query { ...Identified user { id } }
fragment Identified on Root { id }
'''),
      '{...Identified user{id __typename}__typename}'
      'fragment Identified on Root{id}',
    );
  });

  test('an inline fragment on an abstract type at the root adds it', () {
    expect(
      textOf(_schema, 'query { ... on Root { id } }'),
      '{...on Root{id}__typename}',
    );
  });

  test('an abstract fragment inside a root fragment adds it', () {
    expect(
      textOf(_schema, '''
query { ...Outer }
fragment Outer on Query { ...Identified }
fragment Identified on Root { id }
'''),
      '{...Outer __typename}'
      'fragment Identified on Root{id}fragment Outer on Query{...Identified}',
    );
  });

  test('an object fragment at the root adds nothing', () {
    expect(
      textOf(_schema, '''
query { ...Everything }
fragment Everything on Query { id }
'''),
      '{...Everything}fragment Everything on Query{id}',
    );
  });

  test('a subscription root is left as written', () {
    expect(
      textOf(_schema, '''
subscription { ...Identified }
fragment Identified on Root { id }
'''),
      'subscription{...Identified}fragment Identified on Root{id}',
    );
  });

  test('a mutation root gets __typename like a query', () {
    expect(
      textOf(operationSchema, operationDocument, 'RenameUser'),
      r'mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name)'
      '{...UserCard __typename}}fragment UserCard on User{id name}',
    );
  });
}
