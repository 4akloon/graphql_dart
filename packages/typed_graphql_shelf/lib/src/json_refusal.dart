import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A refusal the adapter writes itself, as JSON like the HTTP handler's.
@internal
final class JsonRefusal {
  /// Creates the writer.
  const JsonRefusal();

  /// A response of [status] with one error of [code] and [message].
  Response of(int status, DiagnosticCode code, String message) =>
      withError(status, error(code, message));

  /// A response of [status] with [error] as its only error.
  Response withError(int status, GraphQLError error) => Response(
    status,
    body: jsonEncode(RequestErrorResult(errors: [error]).toJson()),
    headers: const {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  /// The error of [code] and [message].
  GraphQLError error(DiagnosticCode code, String message) => GraphQLError(
    message,
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
