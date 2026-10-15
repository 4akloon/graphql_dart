import 'document_request.dart';
import 'document_result.dart';

/// The rest of the document phase, as an extension's `onDocument` sees it.
///
/// {@category server}
typedef DocumentHandler = Future<DocumentResult> Function(
  DocumentRequest request,
);
