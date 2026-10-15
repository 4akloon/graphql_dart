import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/operation_emitter.dart';
import 'package:typed_graphql_codegen/src/plan/operation_text.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

void main() {
  String emit(String operationName) {
    final fixture = PlanFixture(operationSchema, operationDocument);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere((operation) => operation.name?.value == operationName);
    final writer = DartWriter();
    OperationEmitter(
      OperationText(fixture.schema, fixture.fragments),
    ).emit(operation, '${operationName}Data', writer);
    return writer.text;
  }

  test('a query with variables', () {
    expect(emit('GetUser'), r'''
/// The query `GetUser`.
final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
  /// Creates the query with its [variables].
  const GetUserQuery(this.variables);

  /// The document of `GetUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetUser',
        type: graphql.OperationType.query,
        text: r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){user(id:$id){...UserCard@include(if:$full)role createdAt cursor friends(first:2)@include(if:$withFriends){id name __typename}__typename}}fragment UserCard on User{id name}',
        sha256:
          '198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e',
      );

  /// The variables the query is sent with.
  final GetUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
      GetUserData.decode(data, variables: variablesJson);
}
''');
  });

  test('a query whose document has a fragment and type tests', () {
    expect(emit('FindNode'), r'''
/// The query `FindNode`.
final class FindNodeQuery extends client.GraphQLQuery<FindNodeData> {
  /// Creates the query with its [variables].
  const FindNodeQuery(this.variables);

  /// The document of `FindNode` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'FindNode',
        type: graphql.OperationType.query,
        text: r'query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}...on Bot{model}__typename}}fragment UserCard on User{id name}',
        sha256:
          '7a6b96aae12daef4bcd220864fe9f9d5e3f606c6cde72b347b4c985a3939b1e0',
      );

  /// The variables the query is sent with.
  final FindNodeVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<FindNodeData> decodeData(graphql.JsonObject data) =>
      FindNodeData.decode(data, variables: variablesJson);
}
''');
  });

  test('a query without variables', () {
    expect(emit('Everyone'), '''
/// The query `Everyone`.
final class EveryoneQuery extends client.GraphQLQuery<EveryoneData> {
  /// Creates the query.
  const EveryoneQuery();

  /// The document of `Everyone` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'Everyone',
        type: graphql.OperationType.query,
        text: 'query Everyone{node(id:"1"){id __typename}}',
        sha256:
          '5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61',
      );

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => graphql.JsonObject(const {});

  @override
  graphql.DecodeResult<EveryoneData> decodeData(graphql.JsonObject data) =>
      EveryoneData.decode(data);
}
''');
  });

  test('a mutation', () {
    expect(emit('RenameUser'), r'''
/// The mutation `RenameUser`.
final class RenameUserMutation extends client.GraphQLMutation<RenameUserData> {
  /// Creates the mutation with its [variables].
  const RenameUserMutation(this.variables);

  /// The document of `RenameUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'RenameUser',
        type: graphql.OperationType.mutation,
        text: r'mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name){...UserCard __typename}}fragment UserCard on User{id name}',
        sha256:
          '99b64c8c80d6d3ed8be8cababb9cdafc092f7b125db944902fe6d172681f3020',
      );

  /// The variables the mutation is sent with.
  final RenameUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<RenameUserData> decodeData(graphql.JsonObject data) =>
      RenameUserData.decode(data, variables: variablesJson);
}
''');
  });

  test('a subscription with a header that wraps', () {
    expect(emit('UserChanged'), r'''
/// The subscription `UserChanged`.
final class UserChangedSubscription
    extends client.GraphQLSubscription<UserChangedData> {
  /// Creates the subscription with its [variables].
  const UserChangedSubscription(this.variables);

  /// The document of `UserChanged` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'UserChanged',
        type: graphql.OperationType.subscription,
        text: r'subscription UserChanged($id:ID!){userChanged(id:$id){id name __typename}}',
        sha256:
          '7a4a1e850c31f8be22e726ba1e15417b48ca868176bc43c36a64fa305be990b2',
      );

  /// The variables the subscription is sent with.
  final UserChangedVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<UserChangedData> decodeData(graphql.JsonObject data) =>
      UserChangedData.decode(data, variables: variablesJson);
}
''');
  });

  test('the document carries the SHA-256 of its text', () {
    // printf '%s' 'query Everyone{node(id:"1"){id __typename}}' | sha256sum
    expect(
      emit('Everyone'),
      contains(
        "'5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61'",
      ),
    );
  });
}
