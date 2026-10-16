/// The body of an `HttpResponseData`: a [FixedBody] or a [StreamedBody].
///
/// {@category http}
sealed class HttpResponseBody {
  /// Creates a body.
  const HttpResponseBody();
}

/// A body whose bytes are all known.
///
/// {@category http}
final class FixedBody extends HttpResponseBody {
  /// Creates a body of [bytes], which the handler never changes afterwards.
  const FixedBody(this.bytes);

  /// The bytes to write.
  final List<int> bytes;
}

/// A body written as it comes, such as an event stream.
///
/// The host must write each chunk without buffering and cancel its
/// subscription when the client goes away.
///
/// {@category http}
final class StreamedBody extends HttpResponseBody {
  /// Creates a body of [chunks].
  const StreamedBody(this.chunks);

  /// The chunks to write, in order.
  final Stream<List<int>> chunks;
}
