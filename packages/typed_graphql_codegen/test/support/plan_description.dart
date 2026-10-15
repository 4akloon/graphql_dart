import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';
import 'package:typed_graphql_codegen/src/plan/planned_field.dart';

/// Renders a plan list as text, for tests to compare whole.
final class PlanDescription {
  const PlanDescription();

  String describe(List<PlannedClass> plan) {
    final lines = <String>[];
    for (final planned in plan) {
      switch (planned) {
        case PolymorphicBasePlan():
          final owner = planned.ownerName == null
              ? ''
              : ', of ${planned.ownerName}.${planned.ownerMember}';
          lines.add(
            '${planned.name} (sealed ${planned.role.name} on '
            '${planned.typeName}$owner)',
          );
          for (final field in planned.sharedFields) {
            lines.add('  ${_field(field)}');
          }
          if (planned.holderName case final holder?) {
            lines.add('  fragments: $holder');
          }
          lines.add(
            '  variants: ${planned.variants.map((v) => '${v.typeName}=${v.className}').join(', ')}'
            ', unknown=${planned.unknownName}',
          );
        case DataClassPlan():
          final owner = planned.ownerName == null
              ? ''
              : ', of ${planned.ownerName}.${planned.ownerMember}';
          final base = planned.baseName == null
              ? ''
              : ', implements ${planned.baseName}';
          lines.add(
            '${planned.name} (${planned.role.name} on ${planned.typeName}'
            '$owner$base)',
          );
          for (final field in planned.fields) {
            lines.add('  ${_field(field)}');
          }
          if (planned.holderName case final holder?) {
            final marks = planned.holderOverridesBase ? ' (override)' : '';
            lines.add('  fragments: $holder$marks');
          }
        case FragmentHolderPlan():
          lines.add('${planned.name} (holder of ${planned.ownerName})');
          for (final fragment in planned.fragments) {
            final when = fragment.whenAny.every((list) => list.isEmpty)
                ? ''
                : ' when ${fragment.whenAny.map((list) => list.join(' & ')).join(' | ')}';
            lines.add(
              '  ${fragment.memberName}: ${fragment.className}'
              '${fragment.isConditional ? '?' : ''}$when',
            );
          }
      }
    }
    return lines.join('\n');
  }

  String _field(PlannedField field) {
    final marks = field.isConditional ? ' (conditional)' : '';
    final target = field.className == null ? '' : ' -> ${field.className}';
    final override = field.overridesBase ? '@override ' : '';
    return '$override${field.memberName}: '
        '${const Printer().print(field.type)}'
        ' <- ${field.responseName}$target$marks';
  }
}
