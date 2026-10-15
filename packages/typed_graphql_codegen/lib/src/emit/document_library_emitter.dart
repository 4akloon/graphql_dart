import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_class.dart';
import '../plan/shape_planner.dart';
import 'class_documentation.dart';
import 'dart_writer.dart';
import 'data_class_emitter.dart';
import 'fragment_holder_emitter.dart';
import 'generated_header.dart';
import 'imports.dart';
import 'library_imports.dart';
import 'type_mapper.dart';

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

  /// The text of the library of [documentPath], which defines [fragments] in
  /// document order.
  String emit(String documentPath, List<FragmentDefinition> fragments) {
    final imports = Imports();
    final body = DartWriter();
    final String libraryPath = libraryPathOf(documentPath);
    final plans = [
      for (final fragment in fragments)
        (fragment, planner.planFragment(fragment)),
    ];
    final all = [for (final (_, classes) in plans) ...classes];
    libraryImports.record(imports, libraryPath, all);
    var isFirst = true;
    for (final (fragment, classes) in plans) {
      for (final planned in classes) {
        if (!isFirst) body.line();
        isFirst = false;
        _write(planned, classes, fragment.name.value, body, imports);
      }
    }
    final head = DartWriter();
    const GeneratedHeader().write(head, source: documentPath);
    imports.write(head);
    head.line();
    return all.isEmpty ? head.text : '${head.text}\n${body.text}';
  }

  void _write(
    PlannedClass planned,
    List<PlannedClass> classes,
    String fragmentName,
    DartWriter body,
    Imports imports,
  ) {
    switch (planned) {
      case final DataClassPlan plan:
        final doc = ClassDocumentation(
          classes,
        ).of(plan, fragmentName: fragmentName);
        DataClassEmitter(mapper).emit(plan, doc, body, imports);
      case final FragmentHolderPlan plan:
        const FragmentHolderEmitter().emit(plan, body);
      case PolymorphicBasePlan():
        throw StateError('${planned.name} needs the polymorphic emitter.');
    }
  }
}
