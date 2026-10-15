import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// graphql-js's `execute`, `executeSync` and `graphqlSync` as the ported
/// execution tests use them: the text is parsed with its [Source] (so
/// locations match), run, and the response is compared as JSON with the
/// codes the library adds to `extensions` dropped (spec 18.7 of M5).
///
/// A multi-line Dart literal drops the line break right after its opening
/// quotes, which a graphql-js template literal keeps: a test that checks
/// locations starts its literal with `\n` to restore the line count.
final class ExecutionPort {
  /// Creates the helpers; they keep no state.
  const ExecutionPort();

  /// The options every run starts from: error messages are not masked, as
  /// graphql-js's are not.
  static const ExecutionOptions unmasked = ExecutionOptions(maskErrors: false);

  /// The document of [text], which may be invalid: graphql-js's tests run
  /// documents that were never validated.
  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  /// Executes [text] in [schema] without validating it; the result is a
  /// future only when a resolver waited.
  FutureOr<ResponsePayload> payload<C>(
    ExecutableSchema<C> schema,
    String text, {
    required C context,
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) => schema.execute(
    ValidDocument.assumeValid(schema.schema, parse(text)),
    context: context,
    operationName: operationName,
    variables: variables,
    options: ExecutionOptions(
      rootValue: options.rootValue,
      source: Source(text),
      errorBehavior: options.errorBehavior,
      maskErrors: options.maskErrors,
      includesSuggestions: options.includesSuggestions,
      onError: options.onError,
      maxCoercionErrors: options.maxCoercionErrors,
      maxDepth: options.maxDepth,
      maxSteps: options.maxSteps,
    ),
  );

  /// [payload] for a schema whose context is not read.
  FutureOr<ResponsePayload> run(
    ExecutableSchema<Object?> schema,
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) => payload<Object?>(
    schema,
    text,
    context: null,
    operationName: operationName,
    variables: variables,
    options: options,
  );

  /// The request variables for [plain], the object `jsonDecode` would give
  /// (maps, lists, strings, numbers, booleans and null).
  JsonObject variablesOf(Map<String, Object?> plain) =>
      switch (const JsonReader().read(plain)) {
        DecodeSuccess(value: final JsonObject object) => object,
        _ => throw ArgumentError.value(plain, 'plain', 'is not a JSON object'),
      };

  /// The response of [run] as JSON, awaited.
  Future<Map<String, Object?>> json(
    ExecutableSchema<Object?> schema,
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) async => withoutCodes(
    await run(
      schema,
      text,
      operationName: operationName,
      variables: variables,
      options: options,
    ),
  );

  /// The JSON of [response] with every `extensions.code` dropped, and an
  /// `extensions` object that held nothing else.
  Map<String, Object?> withoutCodes(ResponsePayload response) {
    final json = response.toJson().toJson();
    final errors = json['errors'];
    if (errors is! List<Object?>) {
      return json;
    }
    return {
      ...json,
      'errors': [for (final error in errors) _withoutCode(error)],
    };
  }

  Object? _withoutCode(Object? error) {
    if (error is! Map<String, Object?>) {
      return error;
    }
    final extensions = error['extensions'];
    if (extensions is! Map<String, Object?>) {
      return error;
    }
    final rest = {...extensions}..remove('code');
    return {
      for (final entry in error.entries)
        if (entry.key != 'extensions') entry.key: entry.value,
      if (rest.isNotEmpty) 'extensions': rest,
    };
  }

  /// graphql-js's `graphqlSync`: parse, validate and execute [text], with
  /// each syntax or validation problem as an error with its locations.
  Future<Map<String, Object?>> respond(
    ExecutableSchema<Object?> schema,
    String text, {
    Object? rootValue,
  }) async {
    final source = Source(text);
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source);
    if (parsed is ParseFailure) {
      return problems(parsed.diagnostics, prefix: 'Syntax Error: ');
    }
    final validated = const DocumentValidator().validate(
      schema.schema,
      (parsed as ParseSuccess).document,
      source: source,
    );
    if (validated is InvalidDocument) {
      return problems(validated.diagnostics);
    }
    return withoutCodes(
      await schema.execute(
        validated as ValidDocument,
        context: null,
        options: ExecutionOptions(
          rootValue: rootValue,
          source: source,
          maskErrors: false,
        ),
      ),
    );
  }

  /// [diagnostics] as graphql-js's errors JSON, each message after
  /// [prefix] and with the line and column of its place.
  Map<String, Object?> problems(
    List<Diagnostic> diagnostics, {
    String prefix = '',
  }) => {
    'errors': [
      for (final diagnostic in diagnostics)
        {
          'message': '$prefix${diagnostic.message}',
          if (diagnostic.span case final span?)
            'locations': [
              {'line': span.location.line, 'column': span.location.column},
            ],
        },
    ],
  };
}
