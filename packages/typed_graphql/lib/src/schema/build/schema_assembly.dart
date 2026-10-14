import '../../language/ast/operation_type.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'build_report.dart';
import 'directive_extender.dart';
import 'document_definitions.dart';
import 'element_reader.dart';
import 'member_filter.dart';
import 'schema_definition_reader.dart';
import 'type_extender.dart';
import 'type_reader.dart';
import 'unique_definitions.dart';

/// Builds one schema from the sorted definitions of one document,
/// reporting every construction problem into [report].
final class SchemaAssembly(
  /// Receives the errors and gives the spans.
  final BuildReport report,
) {
  /// Creates an assembly.
  this;

  /// The schema [definitions] define; default root types are taken from
  /// types named `Query`, `Mutation` and `Subscription` for the operations
  /// no schema definition or extension names (spec §3.3.1).
  Schema fromSdl(
    DocumentDefinitions definitions, {
    required bool includesDeferAndStream,
  }) => _apply(
    Schema(includesDeferAndStream: includesDeferAndStream),
    definitions,
    appliesDefaultRoots: definitions.schemas.isEmpty,
  );

  /// [base] with [definitions] applied, as graphql-js's `extendSchema`:
  /// [base] itself when there is no type-system definition or extension.
  Schema extend(Schema base, DocumentDefinitions definitions) {
    if (definitions.hasTypeSystem) {
      return _apply(base, definitions, appliesDefaultRoots: false);
    }
    _reportExecutables(definitions);
    return base;
  }

  Schema _apply(
    Schema base,
    DocumentDefinitions definitions, {
    required bool appliesDefaultRoots,
  }) {
    _reportExecutables(definitions);
    final unique = UniqueDefinitions(report, base);
    final types = TypeExtender(report, base).applyAll(
      _types(base, unique.types(definitions.types)),
      definitions.typeExtensions,
    );
    final header = SchemaDefinitionReader(
      report,
      _elements,
    ).read(base, definitions.schemas, definitions.schemaExtensions);
    final defaults = appliesDefaultRoots
        ? _defaultRoots(types)
        : const <OperationType, String>{};
    return Schema(
      types: types,
      directives: DirectiveExtender(report, base).applyAll(
        _directives(base, unique.directives(definitions.directives)),
        definitions.directiveExtensions,
      ),
      queryTypeName: header.queryTypeName ?? defaults[OperationType.query],
      mutationTypeName:
          header.mutationTypeName ?? defaults[OperationType.mutation],
      subscriptionTypeName:
          header.subscriptionTypeName ?? defaults[OperationType.subscription],
      description: header.description,
      appliedDirectives: header.appliedDirectives,
      includesDeferAndStream: base.includesDeferAndStream,
      span: header.span,
    );
  }

  final ElementReader _elements = ElementReader(report.spans);
  final MemberFilter _filter = MemberFilter(report);

  void _reportExecutables(DocumentDefinitions definitions) {
    for (final executable in definitions.executables) {
      report.error(
        .executableDefinitionInSchema,
        'A schema document cannot hold operations or fragments.',
        executable,
      );
    }
  }

  List<SchemaType> _types(Schema base, List<TypeDefinition> nodes) => [
    ...base.types,
    for (final node in nodes)
      TypeReader(_elements).type(_filter.definition(node)),
  ];

  List<SchemaDirective> _directives(
    Schema base,
    List<DirectiveDefinition> nodes,
  ) => [
    ...base.directives,
    for (final node in nodes) _elements.directive(_filter.directive(node)),
  ];

  Map<OperationType, String> _defaultRoots(List<SchemaType> types) => {
    for (final type in types) ?_defaultRootNames[type.name]: type.name,
  };

  static const Map<String, OperationType> _defaultRootNames = {
    'Query': .query,
    'Mutation': .mutation,
    'Subscription': .subscription,
  };
}
