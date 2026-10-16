import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// `query Hello{hello}`: data is the string `hello`.
final class HelloQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const HelloQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('hello').read(data);
}

/// `query Greet($name:String!){greet(name:$name)}`.
final class GreetQuery extends GraphQLQuery<String> {
  /// Creates the query for [name].
  const GreetQuery(this.name);

  /// The `name` variable.
  final String name;

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Greet',
    type: OperationType.query,
    text: r'query Greet($name:String!){greet(name:$name)}',
    sha256: '4e2feb1a6790b6f16d7d1340acb4e70d97fa0dc940e6a43cd2ff8c5f4d31f550',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject({'name': JsonString(name)});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('greet').read(data);
}

/// `mutation Rename($name:String!){rename(name:$name)}`.
final class RenameMutation extends GraphQLMutation<String> {
  /// Creates the mutation for [name].
  const RenameMutation(this.name);

  /// The `name` variable.
  final String name;

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Rename',
    type: OperationType.mutation,
    text: r'mutation Rename($name:String!){rename(name:$name)}',
    sha256: '1bb30d2c80d17cea066ae8454207397630d460ca2084e2917961574f25b98386',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject({'name': JsonString(name)});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('rename').read(data);
}

/// `subscription Ticks{ticks}`: data is the integer `ticks`.
final class TicksSubscription extends GraphQLSubscription<int> {
  /// Creates the subscription.
  const TicksSubscription();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

/// Reads one string field of `data`, as a generated reader would.
final class StringField {
  /// Creates the reader of [name].
  const StringField(this.name);

  /// The field's response name.
  final String name;

  /// The string at [name] in [data], or a failure at its path.
  DecodeResult<String> read(JsonObject data) => switch (data[name]) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => DecodeFailure('expected a string', path: [PathKey(name)]),
  };
}
