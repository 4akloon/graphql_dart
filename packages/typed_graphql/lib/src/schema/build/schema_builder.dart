import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../../language/ast/document.dart';
import '../../protocol/json_value.dart';
import '../introspection/introspection_reader.dart';
import '../schema.dart';
import 'build_report.dart';
import 'build_result.dart';
import 'document_definitions.dart';
import 'node_spans.dart';
import 'schema_assembly.dart';

/// Builds a schema from SDL (spec §4; R2.2), reporting construction
/// problems as `GQL1xx` diagnostics and never throwing.
///
/// Building does not validate: an unknown type reference is kept, a root
/// may name a type of the wrong kind. Schema validation checks those.
///
/// {@category schema}
final class const SchemaBuilder({
  /// Whether built schemas have `@defer` and `@stream`, which graphql-js
  /// defines and the specification does not yet (R2.6).
  final bool includesDeferAndStream = false,

  /// Whether built schemas have `@cost` and `@listSize` of the IBM GraphQL
  /// Cost Directives draft, which the specification does not define; an
  /// opt-in, so that schemas stay portable.
  final bool includesCostDirectives = false,
}) {
  /// Creates a builder.
  this;

  /// The schema the type-system definitions of [document] define.
  ///
  /// [source] is the text [document] was parsed from: it gives the
  /// elements and the diagnostics their spans, which are null without it.
  BuildResult fromSdl(Document document, {Source? source}) {
    final report = BuildReport(NodeSpans(source));
    final schema = SchemaAssembly(report).fromSdl(
      DocumentDefinitions.of(document),
      includesDeferAndStream: includesDeferAndStream,
      includesCostDirectives: includesCostDirectives,
    );
    return _result(schema, report);
  }

  /// [schema] with the type-system definitions and extensions of
  /// [document] applied (graphql-js's `extendSchema`); [schema] itself when
  /// [document] has none.
  ///
  /// [source] is the text [document] was parsed from, as for [fromSdl];
  /// the elements [schema] already has keep their spans. Whether `@defer`
  /// and `@stream` exist is [schema]'s, not this builder's.
  BuildResult extend(Schema schema, Document document, {Source? source}) {
    final report = BuildReport(NodeSpans(source));
    final extended = SchemaAssembly(
      report,
    ).extend(schema, DocumentDefinitions.of(document));
    return _result(extended, report);
  }

  /// The schema the `data` of an introspection result describes
  /// (graphql-js's `buildClientSchema`; spec §4), such as
  /// `Schema.toIntrospection` writes and a server answers
  /// `IntrospectionQuery.full` with.
  ///
  /// Structural problems are `GQL150` to `GQL155` diagnostics, each
  /// message led by the JSON path of the problem; the elements they are
  /// about are left out of the partial schema. Like [fromSdl], it does not
  /// validate: a field of an input type builds, and schema validation
  /// reports it. Elements have no span; [includesDeferAndStream] and
  /// [includesCostDirectives] do not apply, as the result says whether those
  /// directives exist.
  BuildResult fromIntrospection(JsonValue result) {
    final sink = DiagnosticSink();
    final schema = IntrospectionReader(sink).read(result);
    return sink.hasErrors
        ? BuildFailure(schema, sink.diagnostics)
        : BuildSuccess(schema);
  }

  BuildResult _result(Schema schema, BuildReport report) => report.hasErrors
      ? BuildFailure(schema, report.diagnostics())
      : BuildSuccess(schema);
}
