import 'transport_request.dart';
import 'transport_response.dart';

/// The seam between the HTTP links and an HTTP library: sends one request
/// and returns the answer's status, headers and body stream (spec section
/// 9, R8.4).
///
/// `PackageHttpTransport` adapts any `http.Client`; tests and in-memory
/// servers implement this interface directly. A transport reports a
/// connection problem by throwing an `Exception`, from [send] or from the
/// body stream, and stops the request when its `abortTrigger` completes.
///
/// {@category http}
abstract interface class HttpTransport {
  /// Sends [request] and completes with the answer once its headers have
  /// arrived; the body is read from the answer's stream.
  Future<TransportResponse> send(TransportRequest request);
}
