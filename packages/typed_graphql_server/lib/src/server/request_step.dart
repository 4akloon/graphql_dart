import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'context_factory.dart';
import 'document_entry.dart';
import 'document_step.dart';
import 'execution_job.dart';
import 'execution_step.dart';
import 'operation_lookup.dart';
import 'pipeline_errors.dart';
import 'server_limits.dart';
import 'server_outcome.dart';
import 'server_request.dart';
import 'server_response.dart';

/// The pipeline of section 6 from the length check to the execution. The
/// extension chains of the request, document and execution phases wrap
/// [run], [documentStep] and [executionStep] respectively.
@internal
final class RequestStep<C> {
  /// Creates the step.
  const RequestStep({
    required this.limits,
    required this.documentStep,
    required this.contextFactory,
    required this.executionStep,
    required this.errors,
  });

  /// The limits the length check reads.
  final ServerLimits limits;

  /// The document phase.
  final DocumentStep documentStep;

  /// Builds the context, after every refusal has been passed.
  final ContextFactory<C> contextFactory;

  /// The execution phase.
  final ExecutionStep<C> executionStep;

  /// Makes the refusals.
  final PipelineErrors errors;

  /// Serves [request]; may throw, the caller turns that into a response.
  Future<ServerResponse> run(ServerRequest request) async {
    final text = request.params.query;
    final maxLength = limits.maxDocumentLength;
    if (text != null && maxLength != null && text.length > maxLength) {
      return errors.refusal(
        DiagnosticCode.documentTooLong,
        'The document is longer than the maximum of $maxLength characters.',
      );
    }
    if (text == null || text.isEmpty) {
      return errors.refusal(
        DiagnosticCode.queryRequired,
        'Must provide query string.',
      );
    }
    return switch (documentStep.run(text)) {
      RejectedEntry(errors: final rejected) => errors.rejected(rejected),
      final AcceptedEntry accepted => _accepted(accepted, request),
    };
  }

  Future<ServerResponse> _accepted(
    AcceptedEntry entry,
    ServerRequest request,
  ) async {
    final type = const OperationLookup().typeOf(
      entry.document.document,
      request.params.operationName,
    );
    if (type == OperationType.mutation &&
        request.info.method.toUpperCase() == 'GET') {
      return errors.refusal(
        DiagnosticCode.mutationRequiresPost,
        'A mutation can only be sent with the POST method.',
        outcome: ServerOutcome.methodNotAllowed,
        headers: const {'allow': 'POST'},
      );
    }
    final context = await contextFactory(request.info);
    return executionStep.run(
      ExecutionJob<C>(
        entry: entry,
        operationType: type,
        context: context,
        request: request,
      ),
    );
  }
}
