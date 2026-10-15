import 'package:typed_graphql/typed_graphql.dart';

import '../plan/data_class_role.dart';
import '../plan/operation_text.dart';
import '../plan/planned_class.dart';
import '../plan/shape_planner.dart';
import 'class_documentation.dart';
import 'dart_writer.dart';
import 'data_class_emitter.dart';
import 'fragment_holder_emitter.dart';
import 'generated_header.dart';
import 'imports.dart';
import 'library_imports.dart';
import 'operation_emitter.dart';
import 'polymorphic_base_emitter.dart';
import 'type_mapper.dart';
import 'variables_emitter.dart';

/// Writes the library of one document file: the classes of its fragments
/// (spec §7 "Files").
///
/// {@category codegen}
final class DocumentLibraryEmitter {
  /// Creates the emitter; [planner] plans the classes, [mapper] maps their
  /// types and [libraryImports] decides the imports.
  const DocumentLibraryEmitter(this.planner, this.mapper, this.libraryImports);

  /// The class planner.
  final ShapePlanner planner;

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The recorder of the imports.
  final LibraryImports libraryImports;

  /// The path of the library generated from the document file [documentPath].
  String libraryPathOf(String documentPath) => '$documentPath.dart';

  /// The text of the library of [documentPath], which defines
  /// [definitions] in document order.
  String emit(String documentPath, List<ExecutableDefinition> definitions) {
    final imports = Imports();
    final body = DartWriter();
    final String libraryPath = libraryPathOf(documentPath);
    final plans = [
      for (final definition in definitions) (definition, _plan(definition)),
    ];
    final all = [for (final (_, classes) in plans) ...classes];
    libraryImports.record(imports, libraryPath, all, [
      for (final (definition, classes) in plans)
        if (definition is OperationDefinition && classes.isNotEmpty) definition,
    ]);
    final text = OperationText(planner.schema, planner.fragments);
    var isFirst = true;
    for (final (definition, classes) in plans) {
      if (classes.isEmpty) continue;
      void separate() {
        if (!isFirst) body.line();
        isFirst = false;
      }

      if (definition case final OperationDefinition operation) {
        separate();
        OperationEmitter(text).emit(operation, classes.first.name, body);
        if (operation.variableDefinitions.isNotEmpty) {
          separate();
          VariablesEmitter(mapper).emit(operation, body, imports);
        }
      }
      for (final planned in classes) {
        separate();
        _write(planned, classes, definition, body, imports);
      }
    }
    final head = DartWriter();
    const GeneratedHeader().write(head, source: documentPath);
    imports.write(head);
    head.line();
    return all.isEmpty ? head.text : '${head.text}\n${body.text}';
  }

  List<PlannedClass> _plan(ExecutableDefinition definition) =>
      switch (definition) {
        OperationDefinition() => planner.planOperation(definition),
        FragmentDefinition() => planner.planFragment(definition),
      };

  void _write(
    PlannedClass planned,
    List<PlannedClass> classes,
    ExecutableDefinition definition,
    DartWriter body,
    Imports imports,
  ) {
    final documentation = ClassDocumentation(classes);
    final String? fragmentName = switch (definition) {
      FragmentDefinition(:final name) => name.value,
      OperationDefinition() => null,
    };
    switch (planned) {
      case DataClassPlan(role: DataClassRole.operationData)
          when definition is OperationDefinition:
        DataClassEmitter(mapper).emit(
          planned,
          documentation.ofOperation(definition),
          body,
          imports,
          operation: definition,
        );
      case final DataClassPlan plan:
        final doc = documentation.of(plan, fragmentName: fragmentName);
        DataClassEmitter(mapper).emit(plan, doc, body, imports);
      case final FragmentHolderPlan plan:
        const FragmentHolderEmitter().emit(plan, body);
      case final PolymorphicBasePlan plan:
        final doc = documentation.ofBase(plan, fragmentName: fragmentName);
        PolymorphicBaseEmitter(mapper).emit(plan, doc, body, imports);
    }
  }
}
