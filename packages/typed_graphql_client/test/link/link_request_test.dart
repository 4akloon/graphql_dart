import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  test('of reads the document and the variables of an operation', () {
    final request = LinkRequest.of(const GreetQuery('Ada'));
    expect(request.document, GreetQuery.operationDocument);
    expect(request.variables, JsonObject({'name': const JsonString('Ada')}));
    expect(request.type, OperationType.query);
  });

  test('the body holds the text, the name and the variables', () {
    final request = LinkRequest.of(const GreetQuery('Ada'));
    expect(
      request.body,
      GraphQLRequest(
        query: GreetQuery.operationDocument.text,
        operationName: 'Greet',
        variables: JsonObject({'name': const JsonString('Ada')}),
      ),
    );
  });

  test('the body has no variables when there are none', () {
    expect(LinkRequest.of(const HelloQuery()).body.variables, isNull);
  });

  test('the body has no query when the text is not sent', () {
    final request = LinkRequest.of(
      const HelloQuery(),
    ).withDocumentText(sendsDocumentText: false);
    expect(request.body.query, isNull);
    expect(request.body.operationName, 'Hello');
  });

  test('withExtensions puts the extensions in the body', () {
    final extensions = JsonObject({'trace': const JsonBool(true)});
    final request = LinkRequest.of(
      const HelloQuery(),
    ).withExtensions(extensions);
    expect(request.body.extensions, extensions);
  });

  test('withContext keeps everything else', () {
    final context = LinkContext([
      RequestHeaders({'a': 'b'}),
    ]);
    final request = LinkRequest.of(const GreetQuery('Ada'))
        .withExtensions(JsonObject(const {}))
        .withDocumentText(sendsDocumentText: false)
        .withContext(context);
    expect(request.context, same(context));
    expect(request.extensions, JsonObject(const {}));
    expect(request.sendsDocumentText, isFalse);
    expect(request.variables, JsonObject({'name': const JsonString('Ada')}));
  });

  test('a result is a payload or a failure', () {
    final results = <LinkResult>[
      LinkPayload(ExecutionResult(JsonObject(const {}))),
      const LinkFailure(RequestCancelled()),
    ];
    expect(
      [
        for (final result in results)
          switch (result) {
            LinkPayload() => 'payload',
            LinkFailure() => 'failure',
          },
      ],
      ['payload', 'failure'],
    );
  });
}
