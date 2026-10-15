import '../plan/condition.dart';
import '../plan/planned_class.dart';
import '../plan/planned_fragment.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'reader_factory_writer.dart';
import 'to_json_writer.dart';
import 'value_member.dart';
import 'value_members.dart';

/// Writes the class that holds the fragments spread on a selection (spec §7
/// "Data classes", R7.4).
///
/// {@category codegen}
final class FragmentHolderEmitter {
  /// Creates the emitter.
  const FragmentHolderEmitter();

  static const String _leftOut = '`@include` or `@skip` left it out.';

  /// Writes [plan].
  void emit(FragmentHolderPlan plan, DartWriter writer) {
    final fragments = plan.fragments;
    writer.doc('The fragments spread on [${plan.ownerName}].');
    writer.block('final class ${plan.name} implements client.DataObject', () {
      writer.doc('Creates the fragments.');
      writer.items('const ${plan.name}({', [
        for (final fragment in fragments)
          if (!fragment.isConditional) 'required this.${fragment.memberName}',
        for (final fragment in fragments)
          if (fragment.isConditional) 'this.${fragment.memberName}',
      ], '});');
      writer.line();
      const ReaderFactoryWriter().write(writer, plan.name, [
        for (final fragment in fragments)
          (fragment.memberName, _read(fragment)),
      ]);
      for (final fragment in fragments) {
        writer.line();
        writer.doc(
          fragment.isConditional
              ? 'The fragment `${fragment.fragmentName}`; null when $_leftOut'
              : 'The fragment `${fragment.fragmentName}`.',
        );
        final String question = fragment.isConditional ? '?' : '';
        writer.line(
          'final ${fragment.className}$question ${fragment.memberName};',
        );
      }
      writer.line();
      const ToJsonWriter().write(writer, [
        for (final fragment in fragments) _spread(fragment),
      ]);
      writer.line();
      const ValueMembers().write(writer, plan.name, [
        for (final fragment in fragments)
          ValueMember(fragment.memberName, false),
      ]);
    });
  }

  String _spread(PlannedFragment fragment) => fragment.isConditional
      ? '...?${fragment.memberName}?.toJson().fields'
      : '...${fragment.memberName}.toJson().fields';

  String _read(PlannedFragment fragment) {
    final String read = '${fragment.className}.codec.read(json, context)';
    if (!fragment.isConditional) {
      return read;
    }
    return '${_condition(fragment.whenAny)} ? $read : null';
  }

  // The spread is selected when all conditions of any one list hold.
  String _condition(List<List<Condition>> whenAny) {
    final bool isSeveral = whenAny.length > 1;
    return [
      for (final conditions in whenAny)
        _conjunction(conditions, isParenthesized: isSeveral),
    ].join(' || ');
  }

  String _conjunction(
    List<Condition> conditions, {
    required bool isParenthesized,
  }) {
    final String text = [
      for (final condition in conditions)
        '${condition.isInclude ? '' : '!'}context.flag('
            '${const DartStringLiteral().of(condition.variable)})',
    ].join(' && ');
    return isParenthesized && conditions.length > 1 ? '($text)' : text;
  }
}
