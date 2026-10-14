import '../../language/ast/operation_type.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'build_report.dart';
import 'document_definitions.dart';
import 'element_reader.dart';
import 'member_filter.dart';
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
  /// types named `Query`, `Mutation` and `Subscription` when no schema
  /// definition names the roots (spec §3.3.1).
  Schema fromSdl(
    DocumentDefinitions definitions, {
    required bool includesDeferAndStream,
  }) {
    for (final executable in definitions.executables) {
      report.error(
        .executableDefinitionInSchema,
        'A schema document cannot hold operations or fragments.',
        executable,
      );
    }
    final unique = UniqueDefinitions(
      report,
      Schema(includesDeferAndStream: includesDeferAndStream),
    );
    final filter = MemberFilter(report);
    final elements = ElementReader(report.spans);
    final types = [
      for (final type in unique.types(definitions.types))
        TypeReader(elements).type(filter.definition(type)),
    ];
    final schema = definitions.schemas.firstOrNull;
    final roots = schema == null ? _defaultRoots(types) : _roots(schema);
    return Schema(
      types: types,
      directives: [
        for (final directive in unique.directives(definitions.directives))
          elements.directive(filter.directive(directive)),
      ],
      queryTypeName: roots[OperationType.query],
      mutationTypeName: roots[OperationType.mutation],
      subscriptionTypeName: roots[OperationType.subscription],
      description: schema?.description?.value,
      appliedDirectives: elements.appliedAll(schema?.directives ?? const []),
      includesDeferAndStream: includesDeferAndStream,
      span: schema == null ? null : report.spans.of(schema),
    );
  }

  Map<OperationType, String> _roots(SchemaDefinition schema) => {
    for (final root in schema.operationTypes)
      root.operation: root.type.name.value,
  };

  Map<OperationType, String> _defaultRoots(List<SchemaType> types) => {
    for (final type in types) ?_defaultRootNames[type.name]: type.name,
  };

  static const Map<String, OperationType> _defaultRootNames = {
    'Query': .query,
    'Mutation': .mutation,
    'Subscription': .subscription,
  };
}
