import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/class_documentation.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/data_class_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/fragment_holder_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/polymorphic_base_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import 'plan_fixture.dart';

/// Plans the first operation (or the first fragment) of a document and
/// emits one of its classes, for the emitter tests.
final class ClassEmission(
  /// The schema SDL.
  final String schema,

  /// A valid document.
  final String document,
) {
  this;

  /// The text of the class named [name] of the first operation.
  String emit(String name) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return emitFrom(fixture, planner.planOperation(operation), name);
  }

  /// The text of the class named [name] of the fragment [fragmentName].
  String emitFragment(String fragmentName, String name) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final plan = planner.planFragment(fixture.fragments[fragmentName]!);
    return emitFrom(fixture, plan, name, fragmentName: fragmentName);
  }

  /// The text of [name] among [plan].
  String emitFrom(
    PlanFixture fixture,
    List<PlannedClass> plan,
    String name, {
    String? fragmentName,
  }) {
    final writer = DartWriter();
    final imports = Imports();
    final mapper = TypeMapper(fixture.schema, const {});
    switch (plan.firstWhere((planned) => planned.name == name)) {
      case final DataClassPlan data:
        final doc = ClassDocumentation(
          plan,
        ).of(data, fragmentName: fragmentName);
        DataClassEmitter(mapper).emit(data, doc, writer, imports);
      case final FragmentHolderPlan holder:
        const FragmentHolderEmitter().emit(holder, writer);
      case final PolymorphicBasePlan base:
        final doc = ClassDocumentation(
          plan,
        ).ofBase(base, fragmentName: fragmentName);
        PolymorphicBaseEmitter(mapper).emit(base, doc, writer, imports);
    }
    return writer.text;
  }
}
