import 'package:meta/meta.dart';

/// A media type the HTTP transport can answer with, in the server's order of
/// preference.
@internal
enum ResponseMediaType {
  /// The GraphQL-over-HTTP response type.
  graphqlResponseJson('application', 'graphql-response+json'),

  /// Plain JSON, for clients that predate `application/graphql-response+json`.
  json('application', 'json');

  const ResponseMediaType(this.type, this.subtype);

  /// The top-level type, such as `application`.
  final String type;

  /// The subtype, such as `json`.
  final String subtype;

  /// `type/subtype`.
  String get mediaType => '$type/$subtype';

  /// The `content-type` header value of a body written in this type.
  String get contentType => '$mediaType; charset=utf-8';
}
