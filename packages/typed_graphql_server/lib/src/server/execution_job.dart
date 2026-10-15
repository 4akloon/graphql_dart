import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'document_entry.dart';
import 'server_request.dart';

/// Everything the execution step needs once the pipeline has accepted a
/// request and built its context.
@internal
final class ExecutionJob<C> {
  /// Creates a job.
  const ExecutionJob({
    required this.entry,
    required this.operationType,
    required this.context,
    required this.request,
  });

  /// The accepted document and its source.
  final AcceptedEntry entry;

  /// The kind of the selected operation, null when none is selected.
  final OperationType? operationType;

  /// The context the context factory built.
  final C context;

  /// The request being served.
  final ServerRequest request;
}
