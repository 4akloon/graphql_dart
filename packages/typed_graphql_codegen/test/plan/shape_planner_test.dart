import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  const description = PlanDescription();

  String plan(String document, {String schema = planSchema, int? maxDepth}) {
    final fixture = PlanFixture(schema, document, maxDepth: maxDepth);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return description.describe(planner.planOperation(operation));
  }

  String planFragment(String document) {
    final fixture = PlanFixture(planSchema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final fragment = fixture.document.definitions
        .whereType<FragmentDefinition>()
        .first;
    return description.describe(planner.planFragment(fragment));
  }

  test('the target GetUser plans its classes in order', () {
    final target = Directory('../../.superpowers/m10-target');
    final schema = File('${target.path}/schema.graphql').readAsStringSync();
    final document = File('${target.path}/user.graphql').readAsStringSync();
    expect(
      plan(document, schema: schema),
      r'''
GetUserData (operationData on Query)
  user: User <- user -> GetUserDataUser
GetUserDataUser (nested on User, of GetUserData.user)
  role: Role! <- role
  createdAt: DateTime <- createdAt
  cursor: Cursor <- cursor
  friends: [User!]! <- friends -> GetUserDataUserFriends (conditional)
  fragments: GetUserDataUserFragments
GetUserDataUserFriends (nested on User, of GetUserDataUser.friends)
  id: ID! <- id
  name: String! <- name
GetUserDataUserFragments (holder of GetUserDataUser)
  userCard: UserCard? when $full''',
    );
  });

  test('a fragment plans as its own class', () {
    expect(
      planFragment(
        'query { user { ...UserCard } }\nfragment UserCard on User { id name }',
      ),
      '''
UserCard (fragment on User)
  id: ID! <- id
  name: String <- name''',
    );
  });

  test('an alias and a merged field keep the sub-selections of both nodes', () {
    expect(
      plan(
        'query Q { user { friend { id } other: friend { id } friend { name } } }',
      ),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  friend: User <- friend -> QDataUserFriend
  other: User <- other -> QDataUserOther
QDataUserFriend (nested on User, of QDataUser.friend)
  id: ID! <- id
  name: String <- name
QDataUserOther (nested on User, of QDataUser.other)
  id: ID! <- id''',
    );
  });

  test('a field in a conditional inline fragment is conditional', () {
    expect(
      plan(
        r'query Q($v: Boolean!) { user { ... @include(if: $v) { name } id } }',
      ),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  name: String <- name (conditional)
  id: ID! <- id''',
    );
  });

  test('a field conditional on one node only is not conditional', () {
    expect(
      plan(r'query Q($v: Boolean!) { user { name @include(if: $v) name } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  name: String <- name''',
    );
  });

  test('a selected __typename comes first as typename', () {
    expect(
      plan('query Q { user { id __typename } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  typename: String! <- __typename
  id: ID! <- id''',
    );
  });

  test('an aliased __typename is an ordinary String field', () {
    expect(
      plan('query Q { user { kind: __typename } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  kind: String! <- kind''',
    );
  });

  test('reserved member names get a dollar suffix', () {
    expect(
      plan('query Q { user { hashCode: id typename: name } }'),
      r'''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  hashCode$: ID! <- hashCode
  typename$: String <- typename''',
    );
  });

  test('a fragment spread twice lists both conditions', () {
    expect(
      plan(r'''
query Q($v: Boolean!, $w: Boolean!) {
  user { ...UserCard @include(if: $v) ...UserCard @skip(if: $w) }
}
fragment UserCard on User { id }'''),
      r'''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  fragments: QDataUserFragments
QDataUserFragments (holder of QDataUser)
  userCard: UserCard? when $v | !$w''',
    );
  });

  test('nested classes plan in depth-first pre-order', () {
    expect(
      plan('query Q { user { friend { friend { id } } name } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  friend: User <- friend -> QDataUserFriend
  name: String <- name
QDataUserFriend (nested on User, of QDataUser.friend)
  friend: User <- friend -> QDataUserFriendFriend
QDataUserFriendFriend (nested on User, of QDataUserFriend.friend)
  id: ID! <- id''',
    );
  });

  test('a selection 500 levels deep plans without overflowing', () {
    const depth = 500;
    final document =
        'query Q { user { ${'friend { ' * (depth - 1)}id${' }' * depth} }';
    final lines = plan(document, maxDepth: 2000).split('\n');
    expect(lines.where((line) => line.contains('(nested')), hasLength(depth));
  });

  test('a mutation plans on the mutation root', () {
    expect(
      plan(
        'mutation M { make { id } }',
        schema:
            '$planSchema\ntype Mutation { make: User }\n'
            'schema { query: Query mutation: Mutation }',
      ),
      '''
MData (operationData on Mutation)
  make: User <- make -> MDataMake
MDataMake (nested on User, of MData.make)
  id: ID! <- id''',
    );
  });

  test('a subscription plans on the subscription root', () {
    expect(
      plan(
        'subscription S { born { id } }',
        schema:
            '$planSchema\ntype Subscription { born: User }\n'
            'schema { query: Query subscription: Subscription }',
      ),
      '''
SData (operationData on Subscription)
  born: User <- born -> SDataBorn
SDataBorn (nested on User, of SData.born)
  id: ID! <- id''',
    );
  });
}
