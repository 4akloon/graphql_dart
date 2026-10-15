import 'package:typed_graphql/typed_graphql.dart';

import '../execution/execution_options.dart';
import 'server_request.dart';

/// The input of the execution phase: the accepted document, the context and
/// the options the execution will use (R5.3, R5.15).
///
/// {@category server}
final class ExecutionRequest<C> {
  /// Creates the input.
  const ExecutionRequest({
    required this.request,
    required this.document,
    required this.operationType,
    required this.context,
    required this.options,
  });

  /// The request being served.
  final ServerRequest request;

  /// The validated document.
  final ValidDocument document;

  /// The kind of the selected operation, null when none could be selected
  /// (the execution then reports it).
  final OperationType? operationType;

  /// The context the context factory built.
  final C context;

  /// The options of the execution: the profile's settings and the document's
  /// source.
  final ExecutionOptions options;

  /// The same request with [context] as the context.
  ExecutionRequest<C> withContext(C context) => ExecutionRequest<C>(
    request: request,
    document: document,
    operationType: operationType,
    context: context,
    options: options,
  );

  /// The same request with [options] as the execution options.
  ExecutionRequest<C> withOptions(ExecutionOptions options) =>
      ExecutionRequest<C>(
        request: request,
        document: document,
        operationType: operationType,
        context: context,
        options: options,
      );
}
