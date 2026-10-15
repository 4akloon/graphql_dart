import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/field_collector.dart';
import 'package:typed_graphql_codegen/src/plan/selection_source.dart';

/// A schema and a valid document, for the planner tests.
final class PlanFixture {
  PlanFixture(String sdl, String documentText, {int? maxDepth}) {
    final built = const SchemaBuilder().fromSdl(
      const Parser().parse(Source(sdl)).requireDocument(),
    );
    schema = (built as BuildSuccess).schema;
    document = Parser(
      options: ParserOptions(maxDepth: maxDepth, maxTokens: null),
    ).parse(Source(documentText)).requireDocument();
    final result = const DocumentValidator().validate(
      ValidSchema.assumeValid(schema),
      document,
    );
    if (result is InvalidDocument) {
      throw StateError('Invalid fixture: ${result.diagnostics}');
    }
    for (final definition in document.definitions) {
      if (definition is FragmentDefinition) {
        fragments[definition.name.value] = definition;
      }
    }
  }

  // Assigned in the constructor body, before any use.
  late final Schema schema;
  late final Document document;
  final Map<String, FragmentDefinition> fragments = {};

  FieldCollector get collector => FieldCollector(schema, fragments);

  SchemaType type(String name) => schema.typeNamed(name)!;

  /// The selection set of the first operation.
  SelectionSet get operationSelection =>
      document.definitions.whereType<OperationDefinition>().first.selectionSet;

  /// The selection set of the field `name` in the first operation's set.
  SelectionSet selectionOf(String name) =>
      (operationSelection.selections.whereType<Field>().firstWhere(
        (field) => field.name.value == name,
      )).selectionSet!;

  SelectionSource sourceOf(String name) => SelectionSource(selectionOf(name));
}
