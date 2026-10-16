import '../link/link.dart';
import '../link/link_context.dart';
import '../link/link_request.dart';
import '../operation/graphql_operation.dart';
import 'cancel_token.dart';
import 'client_failure.dart';
import 'graphql_response.dart';
import 'operation_stream.dart';
import 'response_decoder.dart';

/// Sends generated operations through a chain of links and returns typed
/// responses (R8.1).
///
/// Nothing a server or a transport does makes it throw: every outcome is a
/// [GraphQLResponse]. A programmer error, such as a chain whose last link
/// forwards, completes the call with that error.
///
/// {@category client}
final class GraphQLClient({
  /// The chain the requests go through; it must end with a terminating
  /// link.
  required final Link link,
}) {
  /// Creates a client over [link].
  this;

  /// Sends [query] and completes with its response; [context] travels with
  /// the request and [cancelToken] stops it.
  Future<GraphQLResponse<D>> query<D extends Object>(
    GraphQLQuery<D> query, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _first(_responses(query, context, cancelToken));

  /// Sends [mutation] and completes with its response; [context] travels
  /// with the request and [cancelToken] stops it.
  Future<GraphQLResponse<D>> mutate<D extends Object>(
    GraphQLMutation<D> mutation, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _first(_responses(mutation, context, cancelToken));

  /// Starts [subscription] when the stream is listened to and gives one
  /// response per event; cancelling the stream's subscription, or
  /// [cancelToken], ends it.
  Stream<GraphQLResponse<D>> subscribe<D extends Object>(
    GraphQLSubscription<D> subscription, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _responses(subscription, context, cancelToken);

  Stream<GraphQLResponse<D>> _responses<D extends Object>(
    GraphQLOperation<D> operation,
    LinkContext context,
    CancelToken? cancelToken,
  ) => OperationStream(
    link,
    LinkRequest.of(operation, context: context),
    ResponseDecoder(operation),
    cancelToken,
  ).stream;

  /// The first response of [responses]; taking it cancels the
  /// subscription, which ends the request in every link.
  ///
  /// `firstWhere`, not `await for`: leaving an `await for` awaits the
  /// cancel future, which for a synchronous cancel is a root-zone future,
  /// so under fake time (`fake_async`, Flutter's widget tests) the answer
  /// would only arrive on the real event loop.
  Future<GraphQLResponse<D>> _first<D extends Object>(
    Stream<GraphQLResponse<D>> responses,
  ) => responses.firstWhere(
    (response) => true,
    orElse: () => const GraphQLTransportFailure(
      UnsupportedOperation(
        .linkEndedWithoutResult,
        'The link chain ended without a result.',
      ),
    ),
  );
}
