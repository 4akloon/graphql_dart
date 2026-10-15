import 'package:typed_graphql/typed_graphql.dart';

import 'operation_document.dart';

/// A generated operation with its variables: what a client sends and how it
/// reads the data back (R7.9).
///
/// The three kinds let a client accept only queries where only queries make
/// sense (R8.1).
///
/// {@category operations}
sealed class GraphQLOperation<D extends Object> {
  /// Creates an operation.
  const GraphQLOperation();

  /// The document sent for this operation.
  OperationDocument get document;

  /// The variables as JSON, with only the values that were given.
  JsonObject get variablesJson;

  /// Reads the `data` member of a response to this operation.
  DecodeResult<D> decodeData(JsonObject data);

  /// The request for this operation over HTTP or a socket.
  GraphQLRequest toRequest() => GraphQLRequest(
    query: document.text,
    operationName: document.name,
    variables: variablesJson,
  );
}

/// A generated query.
///
/// {@category operations}
abstract base class GraphQLQuery<D extends Object> extends GraphQLOperation<D> {
  /// Creates a query.
  const GraphQLQuery();
}

/// A generated mutation.
///
/// {@category operations}
abstract base class GraphQLMutation<D extends Object>
    extends GraphQLOperation<D> {
  /// Creates a mutation.
  const GraphQLMutation();
}

/// A generated subscription.
///
/// {@category operations}
abstract base class GraphQLSubscription<D extends Object>
    extends GraphQLOperation<D> {
  /// Creates a subscription.
  const GraphQLSubscription();
}
