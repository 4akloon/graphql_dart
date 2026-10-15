import 'package:typed_graphql/typed_graphql.dart';

/// Reads the text of an introspection result into a schema build.
final class const IntrospectionFileReader() {
  /// Creates a reader.
  this;

  /// Builds the schema [text] holds, a result or a response with a `data`
  /// member; every diagnostic has a place in [source].
  BuildResult read(String text, Source source) {
    final place = SourceSpan(source, 0, 0);
    return switch (const JsonReader().parse(text)) {
      final DecodeFailure failure => _failure(
        'The schema file cannot be read: $failure.',
        place,
      ),
      DecodeSuccess(value: final JsonObject object) => _build(object, place),
      DecodeSuccess() => _failure(
        'The schema file must hold a JSON object.',
        place,
      ),
    };
  }

  BuildResult _build(JsonObject object, SourceSpan place) {
    // A raw HTTP response wraps the result in `data`.
    final data = object['data'];
    final result = const SchemaBuilder(
      includesDeferAndStream: true,
    ).fromIntrospection(data is JsonObject ? data : object);
    return switch (result) {
      BuildSuccess() => result,
      BuildFailure(:final partial, :final diagnostics) => BuildFailure(
        partial,
        [for (final diagnostic in diagnostics) _placed(diagnostic, place)],
      ),
    };
  }

  BuildResult _failure(String message, SourceSpan place) => BuildFailure(
    Schema(),
    [Diagnostic(.invalidSchemaInput, .error, message, span: place)],
  );

  // The core's introspection diagnostics have no span; the file name is
  // what the CLI can print.
  Diagnostic _placed(Diagnostic diagnostic, SourceSpan place) =>
      diagnostic.span != null
      ? diagnostic
      : Diagnostic(
          diagnostic.code,
          diagnostic.severity,
          diagnostic.message,
          span: place,
          related: diagnostic.related,
        );
}
