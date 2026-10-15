import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import '../execution/graphql_exception.dart';
import '../persisted/persisted_query_store.dart';
import '../persisted/trusted_documents.dart';
import 'context_factory.dart';
import 'pipeline_assembly.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'server_extension.dart';
import 'server_profile.dart';
import 'server_request.dart';
import 'server_response.dart';

/// Serves GraphQL requests: parses and validates the document (cached),
/// applies the limits of the [ServerProfile], builds the context and
/// executes (R5.1).
///
/// It knows nothing of HTTP: a transport decodes a [ServerRequest] and
/// writes the [ServerResponse]. Every refusal of the server (length,
/// document, method, limits) comes before the context is built and before
/// any resolver runs; the refusals of the executor (an unknown operation
/// name, invalid variables) come after the context is built.
///
/// {@category server}
final class GraphQLServer<C> {
  /// Creates a server for [schema], building each request's context with
  /// [contextFactory].
  ///
  /// [validationRules] are the base rules; the limit rules of
  /// `profile.limits` are added to them. [onError] is passed to every
  /// execution and sees the unexpected errors of the pipeline before they
  /// are masked. [documentCacheSize] is the most compiled documents kept;
  /// 0 keeps none and a negative size is an [ArgumentError].
  ///
  /// [extensions] hook into the three phases of a request; the first is the
  /// outermost and sees even the requests the built-in checks (CSRF
  /// prevention) refuse.
  ///
  /// [persistedQueries] turns on automatic persisted queries (R5.4): a
  /// request may send only the SHA-256 of a document the store holds. Without
  /// a store, a request that sends only a hash is refused with `GQL412`.
  ///
  /// [trustedDocuments] runs only the documents it holds, named by their
  /// hash or sent as their exact text. It cannot be combined with
  /// [persistedQueries], which would let a client register any document:
  /// both are an [ArgumentError].
  factory GraphQLServer({
    required ExecutableSchema<C> schema,
    required ContextFactory<C> contextFactory,
    ServerProfile profile = ServerProfile.production,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
    List<ServerExtension<C>> extensions = const [],
    PersistedQueryStore? persistedQueries,
    TrustedDocuments? trustedDocuments,
  }) {
    if (persistedQueries != null && trustedDocuments != null) {
      throw ArgumentError(
        'Automatic persisted queries would let a client register any '
            'document, which trusted documents forbid.',
        'persistedQueries',
      );
    }
    final assembly = PipelineAssembly<C>(
      schema: schema,
      contextFactory: contextFactory,
      profile: profile,
      validationRules: validationRules,
      onError: onError,
      documentCacheSize: documentCacheSize,
      extensions: extensions,
      persistedQueries: persistedQueries,
      trustedDocuments: trustedDocuments,
    );
    return GraphQLServer._(assembly.errors, assembly.handler());
  }

  GraphQLServer._(this._errors, this._request);

  final PipelineErrors _errors;
  final RequestHandler _request;

  /// Serves [request]. It never throws: a failure is a response.
  ///
  /// A [GraphQLException] from the context factory is a request error; any
  /// other error goes to the error hook and is masked by the profile.
  Future<ServerResponse> handle(ServerRequest request) async {
    try {
      return await _request(request);
    } on GraphQLException catch (exception) {
      return _errors.exception(exception);
    } on Object catch (error, stackTrace) {
      // The outermost boundary, as M5 catches what a resolver throws: user
      // code may throw anything and the caller must still get a response.
      return _errors.internal(error, stackTrace);
    }
  }
}
