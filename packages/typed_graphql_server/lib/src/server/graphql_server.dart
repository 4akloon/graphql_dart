import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import '../execution/graphql_exception.dart';
import 'context_factory.dart';
import 'csrf_extension.dart';
import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_length.dart';
import 'document_step.dart';
import 'execution_step.dart';
import 'extension_chain.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'request_step.dart';
import 'server_extension.dart';
import 'server_limits.dart';
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
  factory GraphQLServer({
    required ExecutableSchema<C> schema,
    required ContextFactory<C> contextFactory,
    ServerProfile profile = ServerProfile.production,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
    List<ServerExtension<C>> extensions = const [],
  }) {
    final errors = PipelineErrors(
      maskErrors: profile.maskErrors,
      onError: onError,
    );
    final length = DocumentLength(profile.limits.maxDocumentLength, errors);
    // The user's extensions come first (outermost), then the built-in ones
    // in a fixed order, so no list order puts an unchecked step before a
    // security check. M6c adds the trusted-document and APQ extensions here.
    final chain = ExtensionChain<C>([
      ...extensions,
      if (profile.csrfPrevention case final csrf?)
        CsrfExtension<C>(csrf, errors),
    ]);
    final executionStep = ExecutionStep<C>(schema, profile, onError);
    final request = RequestStep<C>(
      length: length,
      documentPhase: chain.document(
        DocumentStep(
          DocumentCache(documentCacheSize),
          _compiler(schema.schema, profile, validationRules),
          length,
          errors,
        ).run,
      ),
      contextFactory: contextFactory,
      executionStep: executionStep,
      executionPhase: chain.execution(executionStep.run),
      errors: errors,
    );
    return GraphQLServer._(errors, chain.request(request.run));
  }

  GraphQLServer._(this._errors, this._request);

  final PipelineErrors _errors;
  final RequestHandler _request;

  static DocumentCompiler _compiler(
    ValidSchema schema,
    ServerProfile profile,
    List<ValidationRule> validationRules,
  ) => DocumentCompiler(
    Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
    DocumentValidator(
      rules: [...validationRules, ..._limitRules(profile.limits)],
      includesSuggestions: profile.includesSuggestions,
    ),
    schema,
  );

  static List<ValidationRule> _limitRules(ServerLimits limits) => [
    if (limits.maxDepth case final maxDepth?) MaxDepthRule(maxDepth: maxDepth),
    if (limits.maxAliases case final maxAliases?)
      MaxAliasesRule(maxAliases: maxAliases),
    if (limits.maxDirectives case final maxDirectives?)
      MaxDirectivesRule(maxDirectives: maxDirectives),
  ];

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
