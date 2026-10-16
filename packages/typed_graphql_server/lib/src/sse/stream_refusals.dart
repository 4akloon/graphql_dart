import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/http_response_data.dart';
import '../http/transport_errors.dart';

/// The refusals every request of single connection mode can get.
@internal
final class StreamRefusals {
  /// Creates the refusals, made by [errors].
  const StreamRefusals(this.errors);

  /// Makes the JSON responses.
  final TransportErrors errors;

  /// `404` `GQL433`: no reservation holds the token.
  HttpResponseData notFound() => errors.refusal(
    404,
    DiagnosticCode.eventStreamNotFound,
    'No event stream is reserved for this token.',
  );
}
