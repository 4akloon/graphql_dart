import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'csrf_prevention.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'server_extension.dart';
import 'server_request.dart';
import 'server_response.dart';

/// The request-phase check of [CsrfPrevention] (R5.4, R5.15): a request it
/// does not allow is `GQL403`. The server places it inside the user's
/// extensions, so their hooks see the refusal.
@internal
final class CsrfExtension<C> extends ServerExtension<C> {
  /// Creates the extension for [prevention], refusing through [errors].
  const CsrfExtension(this.prevention, this.errors);

  /// The rule that decides.
  final CsrfPrevention prevention;

  /// Makes the refusal.
  final PipelineErrors errors;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async {
    if (prevention.allows(request.info)) return next(request);
    return errors.refusal(
      DiagnosticCode.csrfRequestBlocked,
      prevention.refusal,
    );
  }
}
