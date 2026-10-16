import 'batch_policy.dart';

/// The settings of `GraphQLHttpHandler`: the limits on what a client may send
/// and how results are reported (R5.5).
///
/// Every limit is checked by the handler's constructor, which throws an
/// `ArgumentError` naming the option for a value that makes no sense.
///
/// {@category http}
final class HttpOptions {
  /// Creates the options; the defaults suit a public endpoint.
  const HttpOptions({
    this.maxBodyBytes = 1048576,
    this.bodyTimeout = const Duration(seconds: 30),
    this.maxJsonDepth = 64,
    this.maxUriLength = 8192,
    this.usesPartialSuccessStatus = true,
    this.batching,
  });

  /// The longest request body accepted, in bytes; a longer one is refused with
  /// `413` (`GQL423`), by its `content-length` before it is read or by a
  /// running count while it is.
  final int maxBodyBytes;

  /// How long the whole body may take to arrive; a slower client is refused
  /// with `408` (`GQL427`).
  final Duration bodyTimeout;

  /// The deepest nesting of arrays and objects accepted in the JSON body and
  /// in the JSON parameters of a `GET`; a deeper one is refused with `400`
  /// (`GQL424`).
  final int maxJsonDepth;

  /// The longest request URI accepted, in characters; a longer one is refused
  /// with `414` (`GQL426`) before anything else is looked at.
  final int maxUriLength;

  /// Whether a result that holds errors is sent with status `294` when the
  /// client accepts `application/graphql-response+json`, which tells a client
  /// that reads only the status that the result is partial.
  ///
  /// A client that does not accept that media type always gets `200`.
  final bool usesPartialSuccessStatus;

  /// How batches are run, or null, the default, to refuse them (`GQL428`).
  final BatchPolicy? batching;
}
