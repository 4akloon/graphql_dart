import 'package:typed_graphql/typed_graphql.dart';

import '../operation/graphql_operation.dart';
import '../operation/operation_document.dart';
import 'link_context.dart';

/// A request as it goes through the links: the operation's document and
/// variables, extensions, and the per-request [context].
///
/// It is immutable; a link that changes something forwards a copy made
/// with [withContext], [withExtensions] or [withDocumentText].
///
/// {@category link}
final class LinkRequest({
  /// The document of the operation, with its name, type and hash.
  required final OperationDocument document,

  /// The values of the operation's variables.
  required final JsonObject variables,

  /// Extra data for the server, such as a persisted query hash.
  final JsonObject? extensions,

  /// The per-request information links read and write.
  final LinkContext context = const LinkContext.empty(),

  /// Whether the document text is sent; the persisted query link turns
  /// it off to send the hash alone.
  final bool sendsDocumentText = true,
}) {
  /// Creates a request.
  this;

  /// The request for [operation] with [context].
  LinkRequest.of(
    GraphQLOperation<Object> operation, {
    LinkContext context = const LinkContext.empty(),
  }) : this(
         document: operation.document,
         variables: operation.variablesJson,
         context: context,
       );

  /// Whether the operation is a query, a mutation or a subscription.
  OperationType get type => document.type;

  /// The request as it is sent: without `query` when [sendsDocumentText]
  /// is false, without `variables` when there are none.
  GraphQLRequest get body => GraphQLRequest(
    query: sendsDocumentText ? document.text : null,
    operationName: document.name,
    variables: variables.fields.isEmpty ? null : variables,
    extensions: extensions,
  );

  /// This request with [context] in place of its own.
  LinkRequest withContext(LinkContext context) => LinkRequest(
    document: document,
    variables: variables,
    extensions: extensions,
    context: context,
    sendsDocumentText: sendsDocumentText,
  );

  /// This request with [extensions] in place of its own.
  LinkRequest withExtensions(JsonObject? extensions) => LinkRequest(
    document: document,
    variables: variables,
    extensions: extensions,
    context: context,
    sendsDocumentText: sendsDocumentText,
  );

  /// This request sending its document text or not.
  LinkRequest withDocumentText({required bool sendsDocumentText}) =>
      LinkRequest(
        document: document,
        variables: variables,
        extensions: extensions,
        context: context,
        sendsDocumentText: sendsDocumentText,
      );

  @override
  String toString() => 'LinkRequest(${document.name})';
}
