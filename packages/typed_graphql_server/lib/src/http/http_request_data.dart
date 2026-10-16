import 'dart:async';

import '../cancellation/cancel_signal.dart';
import '../server/header_names.dart';

/// One HTTP request as a host hands it to `GraphQLHttpHandler`, without any
/// tie to a web framework (R5.5).
///
/// {@category http}
final class HttpRequestData {
  /// Creates a request.
  ///
  /// [headers] names are lower-cased and repeated values should already be
  /// joined with `, `. [body] is read at most once, and only when the
  /// handler needs it. [source] is the host's own request object, which the
  /// library never reads.
  HttpRequestData({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.body = const Stream<List<int>>.empty(),
    this.source,
    this.cancelSignal,
  }) : headers = const HeaderNames().lowerCased(headers);

  /// The HTTP method as the host gave it; the handler compares it ignoring
  /// case.
  final String method;

  /// The full URI, query string included.
  final Uri uri;

  /// The headers, unmodifiable, with lower-case names.
  final Map<String, String> headers;

  /// The body, a stream so the handler can stop reading at its size limit;
  /// a host that has the bytes passes `Stream.value(bytes)`.
  ///
  /// A request refused before its body is read (`415`, or `413` by the
  /// declared length) leaves the stream unlistened: the host must drain it or
  /// close the connection.
  final Stream<List<int>> body;

  /// The host's own request object, never read by the library.
  final Object? source;

  /// Cancelled by the host when the client goes away, so the handler can stop
  /// the work nobody waits for.
  final CancelSignal? cancelSignal;

  /// The value of the header [name], whatever its case, or null.
  String? header(String name) => headers[name.toLowerCase()];
}
