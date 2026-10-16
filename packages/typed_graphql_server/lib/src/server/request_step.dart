import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'context_factory.dart';
import 'cost_limit.dart';
import 'document_handler.dart';
import 'document_length.dart';
import 'document_request.dart';
import 'document_result.dart';
import 'execution_handler.dart';
import 'execution_request.dart';
import 'execution_step.dart';
import 'operation_lookup.dart';
import 'pipeline_errors.dart';
import 'server_outcome.dart';
import 'server_request.dart';
import 'server_response.dart';

/// The core of the request phase (section 6 of the M6 spec): the length
/// check, the document phase, the operation, the context and the execution
/// phase. The extension chains wrap [run], [documentPhase] and
/// [executionPhase].
@internal
final class RequestStep<C> {
  /// Creates the step.
  const RequestStep({
    required this.length,
    required this.operations,
    required this.documentPhase,
    required this.contextFactory,
    required this.executionStep,
    required this.executionPhase,
    required this.errors,
    this.costLimit,
  });

  /// The length check of the request's query.
  final DocumentLength length;

  /// Finds the operation the request selects.
  final OperationLookup operations;

  /// The document phase with its extensions.
  final DocumentHandler documentPhase;

  /// Builds the context, after every refusal has been passed.
  final ContextFactory<C> contextFactory;

  /// Builds the execution options.
  final ExecutionStep<C> executionStep;

  /// The execution phase with its extensions.
  final ExecutionHandler<C> executionPhase;

  /// Makes the refusals.
  final PipelineErrors errors;

  /// The cost limit, null when the profile has none.
  final CostLimit? costLimit;

  /// Serves [request]; may throw, the caller turns that into a response.
  Future<ServerResponse> run(ServerRequest request) async {
    final text = request.params.query;
    if (length.violation(text) case final violation?) {
      return errors.rejected([violation]);
    }
    final result = await documentPhase(DocumentRequest(request, text: text));
    return switch (result) {
      DocumentRejected(errors: final rejected) => errors.rejected(rejected),
      final DocumentAccepted accepted => _accepted(accepted, request),
    };
  }

  // An allow-list: only POST may change state (GraphQL over HTTP), so an
  // unknown or empty method fails closed.
  bool _mayMutate(String method) => method.toUpperCase() == 'POST';

  // No operation selected: the executor reports it.
  SingleResponse? _typeRefusal(OperationType? type, ServerRequest request) {
    if (type == null || request.allowedOperationTypes.contains(type)) {
      return null;
    }
    return errors.refusal(
      DiagnosticCode.operationTypeNotAllowed,
      'A ${_typeName(type)} is not allowed in this request.',
    );
  }

  String _typeName(OperationType type) => switch (type) {
    OperationType.query => 'query',
    OperationType.mutation => 'mutation',
    OperationType.subscription => 'subscription',
  };

  Future<ServerResponse> _accepted(
    DocumentAccepted accepted,
    ServerRequest request,
  ) async {
    final document = accepted.document.document;
    final operation = operations.operationOf(
      document,
      request.params.operationName,
    );
    final type = operation?.operation;
    if (type == OperationType.mutation && !_mayMutate(request.info.method)) {
      return errors.refusal(
        DiagnosticCode.mutationRequiresPost,
        'A mutation can only be sent with the POST method.',
        outcome: ServerOutcome.methodNotAllowed,
        headers: const {'allow': 'POST'},
      );
    }
    if (_typeRefusal(type, request) case final refusal?) return refusal;
    if (_costRefusal(accepted, operation, request) case final refusal?) {
      return refusal;
    }
    final context = await contextFactory(request.info);
    return executionPhase(
      ExecutionRequest<C>(
        request: request,
        document: accepted.document,
        operationType: type,
        context: context,
        options: executionStep.optionsFor(
          accepted.source,
          type,
          request.cancelSignal,
        ),
      ),
    );
  }

  // No operation selected: the executor reports it.
  SingleResponse? _costRefusal(
    DocumentAccepted accepted,
    OperationDefinition? operation,
    ServerRequest request,
  ) {
    final violation = operation == null
        ? null
        : costLimit?.violation(
            accepted.document.document,
            accepted.source,
            operation,
            request,
          );
    return violation == null ? null : errors.rejected([violation]);
  }
}
