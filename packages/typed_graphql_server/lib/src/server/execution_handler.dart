import 'execution_request.dart';
import 'server_response.dart';

/// The rest of the execution phase, as an extension's `onExecute` sees it.
///
/// {@category server}
typedef ExecutionHandler<C> = Future<ServerResponse> Function(
  ExecutionRequest<C> request,
);
