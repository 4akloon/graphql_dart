import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';
import '../build/built_ins.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'directive_definition_reader.dart';
import 'introspection_object.dart';
import 'member_reader.dart';
import 'named_type_reader.dart';
import 'type_ref_reader.dart';

/// Reads the `data` of an introspection result into a schema (graphql-js's
/// `buildClientSchema`), reporting every structural problem into [sink].
///
/// The built-in scalars and introspection types the result lists are the
/// schema's built-ins, not declared types; so are the built-in directives,
/// and `@defer` or `@stream` turn on `includesDeferAndStream`. A result
/// without `directives` has none declared, as graphql-js reads it.
final class IntrospectionReader(
  /// Where problems are reported.
  final DiagnosticSink sink,
) {
  /// Creates a reader.
  this;

  /// The schema [result] describes, with every element that read without
  /// a problem.
  Schema read(JsonValue result) {
    final root = _schemaObject(result);
    if (root == null) {
      return Schema();
    }
    final types = root.list('types') ?? const [];
    final references = TypeRefReader({
      for (final type in types)
        if (type.json['name'] case JsonString(:final value)) value,
    });
    final members = MemberReader(references);
    // In graphql-js's order: types, roots, directives.
    final declaredTypes = [
      for (final type in types)
        if (!_isBuiltInType(type)) ?NamedTypeReader(members).read(type),
    ];
    final (query, mutation, subscription) = (
      _root(root, 'queryType', references),
      _root(root, 'mutationType', references),
      _root(root, 'subscriptionType', references),
    );
    final directives = _directives(root, DirectiveDefinitionReader(members));
    return Schema(
      types: declaredTypes,
      directives: [
        for (final directive in directives)
          if (!_isBuiltInDirective(directive)) directive,
      ],
      queryTypeName: query,
      mutationTypeName: mutation,
      subscriptionTypeName: subscription,
      description: root.optionalString('description'),
      includesDeferAndStream: directives.any(_isDeferOrStream),
    );
  }

  IntrospectionObject? _schemaObject(JsonValue result) {
    if (result case JsonObject(fields: {'__schema': final JsonObject root})) {
      return IntrospectionObject(
        root,
        sink,
        steps: const [PathKey('__schema')],
      );
    }
    const message =
        'Invalid or incomplete introspection result. Ensure that you are '
        'passing "data" property of introspection response and no "errors" '
        'was returned alongside.';
    sink.report(
      Diagnostic(
        .invalidIntrospectionResult,
        .error,
        const DecodeFailure(message).toString(),
      ),
    );
    return null;
  }

  String? _root(IntrospectionObject root, String key, TypeRefReader types) =>
      switch (root.optionalObject(key)) {
        final reference? => types.named(reference),
        null => null,
      };

  List<SchemaDirective> _directives(
    IntrospectionObject root,
    DirectiveDefinitionReader reader,
  ) => [
    for (final directive
        in root.optionalList('directives') ?? const <IntrospectionObject>[])
      ?reader.read(directive),
  ];

  bool _isBuiltInType(IntrospectionObject type) => switch (type.json['name']) {
    JsonString(:final value) => const BuiltIns().typeNamed(value) != null,
    _ => false,
  };

  bool _isBuiltInDirective(SchemaDirective directive) =>
      const BuiltIns().directiveNamed(directive.name) != null ||
      _isDeferOrStream(directive);

  bool _isDeferOrStream(SchemaDirective directive) =>
      directive.name == 'defer' || directive.name == 'stream';
}
