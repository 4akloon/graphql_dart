import 'server_request.dart';

/// The input of the document phase: the request and the document text found
/// so far (R5.3).
///
/// {@category server}
final class DocumentRequest {
  /// Creates the input for [request] with the document [text], null when
  /// there is none yet.
  const DocumentRequest(this.request, {this.text});

  /// The request being served.
  final ServerRequest request;

  /// The document text so far: first `request.params.query`, then whatever
  /// an extension put in its place; null when there is none.
  final String? text;

  /// The same request with [text] as the document text.
  DocumentRequest withText(String? text) =>
      DocumentRequest(request, text: text);
}
