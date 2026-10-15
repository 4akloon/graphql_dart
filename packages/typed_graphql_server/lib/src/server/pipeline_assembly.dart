import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import 'context_factory.dart';
import 'cost_limit.dart';
import 'csrf_extension.dart';
import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_handler.dart';
import 'document_length.dart';
import 'document_step.dart';
import 'execution_step.dart';
import 'extension_chain.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'request_step.dart';
import 'server_extension.dart';
import 'server_profile.dart';

/// Builds the handlers of a server from its settings, once: the extension
/// chains around the core steps. M6c adds its steps to [handler].
@internal
final class PipelineAssembly<C> {
  /// Creates the assembly; the arguments are those of `GraphQLServer`.
  PipelineAssembly({
    required this.schema,
    required this.contextFactory,
    required this.profile,
    required this.validationRules,
    required this.onError,
    required this.documentCacheSize,
    required this.extensions,
  }) : errors = PipelineErrors(
         maskErrors: profile.maskErrors,
         onError: onError,
       );

  /// The schema that executes.
  final ExecutableSchema<C> schema;

  /// Builds each request's context.
  final ContextFactory<C> contextFactory;

  /// The settings of the server.
  final ServerProfile profile;

  /// The base validation rules; the limit rules are added to them.
  final List<ValidationRule> validationRules;

  /// The server's error hook.
  final ErrorHook? onError;

  /// The most compiled documents kept.
  final int documentCacheSize;

  /// The user's extensions, outermost first.
  final List<ServerExtension<C>> extensions;

  /// Makes the refusals and the unexpected-error responses.
  final PipelineErrors errors;

  /// The handler of the request phase, with every extension around it.
  RequestHandler handler() {
    final length = DocumentLength(profile.limits.maxDocumentLength, errors);
    // The user's extensions are outermost, then the built-in ones in a fixed
    // order, so no list order puts a step before a security check. M6c adds
    // the trusted-document and APQ extensions here.
    final chain = ExtensionChain<C>([
      ...extensions,
      if (profile.csrfPrevention case final csrf?)
        CsrfExtension<C>(csrf, errors),
    ]);
    final executionStep = ExecutionStep<C>(schema, profile, onError);
    final request = RequestStep<C>(
      length: length,
      documentPhase: chain.document(_documentStep(length)),
      contextFactory: contextFactory,
      executionStep: executionStep,
      executionPhase: chain.execution(executionStep.run),
      errors: errors,
      costLimit: _costLimit(),
    );
    return chain.request(request.run);
  }

  DocumentHandler _documentStep(DocumentLength length) => DocumentStep(
    DocumentCache(documentCacheSize),
    _compiler(),
    length,
    errors,
  ).run;

  DocumentCompiler _compiler() => DocumentCompiler(
    Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
    DocumentValidator(
      rules: [...validationRules, ..._limitRules()],
      includesSuggestions: profile.includesSuggestions,
    ),
    schema.schema,
  );

  CostLimit? _costLimit() => switch (profile.limits.maxCost) {
    final maxCost? => CostLimit(
      CostAnalysis(
        schema.schema.schema,
        defaultListSize: profile.limits.defaultListSize,
      ),
      maxCost,
    ),
    null => null,
  };

  List<ValidationRule> _limitRules() {
    final limits = profile.limits;
    return [
      if (limits.maxDepth case final maxDepth?)
        MaxDepthRule(maxDepth: maxDepth),
      if (limits.maxAliases case final maxAliases?)
        MaxAliasesRule(maxAliases: maxAliases),
      if (limits.maxDirectives case final maxDirectives?)
        MaxDirectivesRule(maxDirectives: maxDirectives),
    ];
  }
}
