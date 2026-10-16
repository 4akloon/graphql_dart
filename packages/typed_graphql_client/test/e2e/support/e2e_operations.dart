import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../../support/test_operations.dart';

/// `query Partial{hello broken}`: `broken` fails, `hello` is the data.
final class PartialQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const PartialQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Partial',
    type: OperationType.query,
    text: 'query Partial{hello broken}',
    sha256: '07e000c279847cbe0d5541f498b549a3c88c3a162a6303002bd4949188141b3c',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('hello').read(data);
}

/// `query Unknown{nope}`: the schema has no field `nope`.
final class UnknownFieldQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const UnknownFieldQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Unknown',
    type: OperationType.query,
    text: 'query Unknown{nope}',
    sha256: '2271bbec64e5cd1210f83921cd7205cc41d186daefd83e73736669b8352b8e6e',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('nope').read(data);
}
