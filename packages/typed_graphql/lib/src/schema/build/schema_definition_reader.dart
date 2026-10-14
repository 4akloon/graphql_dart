import '../../language/ast/operation_type.dart';
import '../../language/ast/operation_type_definition.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/ast/type_system_extension.dart';
import '../model/named_type_reference.dart';
import '../schema.dart';
import 'build_report.dart';
import 'element_reader.dart';

/// Applies the schema definition and the schema extensions of a document
/// to a schema: root operation types, description, applied directives and
/// span (spec §3.3).
///
/// The first definition and the first root type of each operation win;
/// the messages are graphql-js's (`LoneSchemaDefinitionRule`,
/// `UniqueOperationTypesRule`).
final class SchemaDefinitionReader(
  /// Receives the errors and gives the spans.
  final BuildReport report,

  /// Reads the applied directives.
  final ElementReader elements,
) {
  /// Creates a reader.
  this;

  /// [base] with [definitions] and [extensions] applied: the definition
  /// first, then the extensions in document order; its types and
  /// directives are left as they are.
  Schema read(
    Schema base,
    List<SchemaDefinition> definitions,
    List<SchemaExtension> extensions,
  ) {
    final definition = _definition(base, definitions);
    final roots = _roots(base, [
      ...?definition?.operationTypes,
      for (final extension in extensions) ...extension.operationTypes,
    ]);
    return Schema(
      types: base.types,
      directives: base.directives,
      queryTypeName: roots[OperationType.query]?.name,
      mutationTypeName: roots[OperationType.mutation]?.name,
      subscriptionTypeName: roots[OperationType.subscription]?.name,
      rootTypeSpans: {
        for (final MapEntry(:key, :value) in roots.entries) key: ?value.span,
      },
      description: definition?.description?.value ?? base.description,
      appliedDirectives: [
        ...base.appliedDirectives,
        ...elements.appliedAll(definition?.directives ?? const []),
        for (final extension in extensions)
          ...elements.appliedAll(extension.directives),
      ],
      includesDeferAndStream: base.includesDeferAndStream,
      span:
          base.span ??
          (definition == null ? null : report.spans.of(definition)),
    );
  }

  /// The definition to apply: the first, unless [base] already has a
  /// schema (a root type or a definition), as graphql-js decides.
  SchemaDefinition? _definition(Schema base, List<SchemaDefinition> nodes) {
    final hasSchema =
        base.span != null ||
        OperationType.values.any((operation) {
          return base.rootTypeName(operation) != null;
        });
    for (final (index, node) in nodes.indexed) {
      if (hasSchema) {
        report.error(
          .duplicateSchemaDefinition,
          'Cannot define a new schema within a schema extension.',
          node,
        );
      } else if (index > 0) {
        report.error(
          .duplicateSchemaDefinition,
          'Must provide only one schema definition.',
          node,
          related: report.spans.of(nodes.first),
        );
      }
    }
    return hasSchema ? null : nodes.firstOrNull;
  }

  /// The root types, each with the span of the name that set it.
  Map<OperationType, NamedTypeReference> _roots(
    Schema base,
    List<OperationTypeDefinition> nodes,
  ) {
    final roots = {
      for (final operation in OperationType.values)
        if (base.rootTypeName(operation) case final name?)
          operation: NamedTypeReference(
            name,
            span: base.rootTypeSpan(operation),
          ),
    };
    final firsts = <OperationType, OperationTypeDefinition>{};
    for (final node in nodes) {
      final operation = node.operation;
      if (base.rootTypeName(operation) != null) {
        report.error(
          .duplicateOperationType,
          'Type for ${operation.name} already defined in the schema. It '
          'cannot be redefined.',
          node,
        );
      } else if (firsts[operation] case final first?) {
        report.error(
          .duplicateOperationType,
          'There can be only one ${operation.name} type in schema.',
          node,
          related: report.spans.of(first),
        );
      } else {
        firsts[operation] = node;
        roots[operation] = elements.references([node.type]).single;
      }
    }
    return roots;
  }
}
