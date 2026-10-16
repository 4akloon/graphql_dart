import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// A terminating link for tests (R8.5): it records every request and
/// answers each with the next queued answer for its operation.
///
/// An answer queued with an `operationName` serves only that operation;
/// one without serves any. Answers are used once, first in, first out. A
/// request with no answer left gets a stream with a [StateError]: a bug in
/// the test, not a response.
///
/// {@category link}
final class MockLink extends Link {
  /// Creates a link with no answer queued.
  MockLink();

  final List<LinkRequest> _requests = [];
  final List<({String? operationName, Stream<LinkResult> Function() open})>
  _answers = [];

  /// Every request received, in order.
  List<LinkRequest> get requests => List.unmodifiable(_requests);

  /// How many queued answers no request has used yet.
  int get pendingAnswerCount => _answers.length;

  /// Queues [result] as one answer.
  void add(LinkResult result, {String? operationName}) => _answers.add((
    operationName: operationName,
    open: () => Stream.value(result),
  ));

  /// Queues an execution result holding [data] and [errors].
  void addData(
    JsonObject data, {
    List<GraphQLError> errors = const [],
    String? operationName,
  }) => add(
    LinkPayload(ExecutionResult(data, errors: errors)),
    operationName: operationName,
  );

  /// Queues a request error result holding [errors] (not empty).
  void addErrors(List<GraphQLError> errors, {String? operationName}) => add(
    LinkPayload(RequestErrorResult(errors: errors)),
    operationName: operationName,
  );

  /// Queues [failure] as one answer.
  void addFailure(ClientFailure failure, {String? operationName}) =>
      add(LinkFailure(failure), operationName: operationName);

  /// Queues [results] as one answer of many events, such as a
  /// subscription's; it is listened to once.
  void addStream(Stream<LinkResult> results, {String? operationName}) =>
      _answers.add((operationName: operationName, open: () => results));

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    _requests.add(request);
    final name = request.document.name;
    final index = _answers.indexWhere(
      (answer) => answer.operationName == null || answer.operationName == name,
    );
    if (index < 0) {
      return Stream.error(StateError('MockLink has no answer for $name.'));
    }
    return _answers.removeAt(index).open();
  }
}
