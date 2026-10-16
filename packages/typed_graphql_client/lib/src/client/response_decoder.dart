import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_context.dart';
import '../link/link_result.dart';
import '../operation/graphql_operation.dart';
import 'client_failure.dart';
import 'graphql_response.dart';

/// Turns the untyped results of a link chain into typed responses of one
/// operation (spec section 5).
final class ResponseDecoder<D extends Object> {
  /// Creates the decoder of [_operation]'s results.
  const ResponseDecoder(this._operation);

  final GraphQLOperation<D> _operation;

  /// The response [result] stands for.
  GraphQLResponse<D> decode(LinkResult result) => switch (result) {
    LinkFailure(:final failure) => GraphQLTransportFailure(failure),
    LinkPayload(
      payload: RequestErrorResult(:final errors, :final extensions),
      :final context,
    ) =>
      GraphQLErrors(errors, extensions: extensions, context: context),
    LinkPayload(
      payload: ExecutionResult(data: null, :final errors, :final extensions),
      :final context,
    ) =>
      errors.isEmpty
          ? GraphQLTransportFailure(
              ResponseFormatFailure(
                .malformedResponse,
                'The response has "data": null and no errors.',
              ),
            )
          : GraphQLErrors(errors, extensions: extensions, context: context),
    LinkPayload(
      payload: ExecutionResult(:final data?, :final errors, :final extensions),
      :final context,
    ) =>
      _data(data, errors, extensions, context),
  };

  GraphQLResponse<D> _data(
    JsonObject data,
    List<GraphQLError> errors,
    JsonObject? extensions,
    LinkContext context,
  ) => switch (_operation.decodeData(data)) {
    DecodeSuccess(:final value) => GraphQLData(
      value,
      errors: errors,
      extensions: extensions,
      context: context,
    ),
    final DecodeFailure failure => GraphQLTransportFailure(
      DataFormatFailure(failure, errors: errors),
    ),
  };
}
