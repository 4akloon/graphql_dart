import '../../language/ast/operation_type.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'build_report.dart';
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
  }) {
    final base = Schema(includesDeferAndStream: includesDeferAndStream);
    _reportExecutables(definitions);
    final unique = UniqueDefinitions(report, base);
    final types = TypeExtender(report).applyAll(
      _types(base, unique.types(definitions.types)),
      definitions.typeExtensions,
    );
    final header = SchemaDefinitionReader(
      report,
      _elements,
    ).read(base, definitions.schemas, definitions.schemaExtensions);
    final defaults = definitions.schemas.isEmpty
        ? _defaultRoots(types)
        : const <OperationType, String>{};
    return Schema(
      types: types,
      directives: _directives(base, unique.directives(definitions.directives)),
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

  ElementReader get _elements => ElementReader(report.spans);

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
      TypeReader(_elements).type(MemberFilter(report).definition(node)),
  ];

  List<SchemaDirective> _directives(
    Schema base,
    List<DirectiveDefinition> nodes,
  ) => [
    ...base.directives,
    for (final node in nodes)
      _elements.directive(MemberFilter(report).directive(node)),
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
