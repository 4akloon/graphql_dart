import '../../language/ast/node.dart';
import '../../language/ast/object_field.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../language/printer/printer.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'leaf_value_checker.dart';
import 'value_problem.dart';

/// Whether a constant value, such as a default value or an applied
/// directive's argument, is a value of an input type (spec §3.10 "Input
/// Coercion", graphql-js's `validateInputLiteral` without variables).
///
/// It walks the value with its own stack, so a deeply nested value cannot
/// overflow the call stack, and reports the problems in graphql-js's
/// depth-first order. A type the schema does not have, or one that is not
/// an input type, is the type rules' to report: its values are not
/// checked.
final class ValueChecker(
  /// The schema whose types are known.
  final Schema schema,
) {
  /// Creates the checker for [schema].
  this;

  static const Printer _printer = Printer();

  /// The problems of [value] as a value of [type], in report order.
  List<ValueProblem> check(Value value, TypeRef type) {
    final problems = <ValueProblem>[];
    final work = <_Work>[_Check(value, type, null)];
    while (work.isNotEmpty) {
      switch (work.removeLast()) {
        case _Report(:final problem):
          problems.add(problem);
        case _Check(:final value, :final type, :final path):
          work.addAll(_step(value, type, path).reversed);
      }
    }
    return problems;
  }

  List<_Work> _step(Value value, TypeRef type, _Path? path) =>
      switch ((value, type)) {
        (Variable(), _) => [
          _report(
            'Expected a constant value, found: ${_printer.print(value)}.',
            value,
            path,
          ),
        ],
        (NullValue(), NonNullType()) => [
          _report(
            'Expected value of non-null type "${_printer.print(type)}" not '
            'to be null.',
            value,
            path,
          ),
        ],
        (_, NonNullType(type: final inner)) => [_Check(value, inner, path)],
        (NullValue(), _) => const [],
        (ListValue(:final values), ListType(type: final inner)) => [
          for (final (index, item) in values.indexed)
            _Check(item, inner, _Path(path, index)),
        ],
        // A value that is not a list is a list of one (spec §3.11).
        (_, ListType(type: final inner)) => [_Check(value, inner, path)],
        (_, NamedType(:final name)) => switch (schema.typeNamed(name.value)) {
          final InputObjectType object => _object(value, object, path),
          final type? => [
            if (const LeafValueChecker().errorOf(value, type) case final m?)
              _report(m, value, path),
          ],
          null => const [],
        },
      };

  List<_Work> _object(Value value, InputObjectType type, _Path? path) {
    if (value is! ObjectValue) {
      return [
        _report(
          'Expected value of type "${type.name}" to be an object, found: '
          '${_printer.print(value)}.',
          value,
          path,
        ),
      ];
    }
    // Only for lookups; as graphql-js's keyMap, a repeated field's last
    // value counts.
    final given = {for (final field in value.fields) field.name.value: field};
    return [
      for (final field in type.fields)
        if (given[field.name] case final node?)
          _Check(node.value, field.type, _Path(path, field.name))
        else if (field.type is NonNullType && field.defaultValue == null)
          _report(
            'Expected value of type "${type.name}" to include required field '
            '"${field.name}", found: ${_printer.print(value)}.',
            value,
            path,
          ),
      for (final node in value.fields)
        if (type.fieldNamed(node.name.value) == null)
          _report(
            'Expected value of type "${type.name}" not to include unknown '
            'field "${node.name.value}", found: ${_printer.print(value)}.',
            node,
            path,
          ),
      if (type.isOneOf) ?_oneOf(value, type, path),
    ];
  }

  // Spec §3.10 "OneOf Input Objects": exactly one field, not null.
  _Work? _oneOf(ObjectValue value, InputObjectType type, _Path? path) {
    final known = [
      for (final node in value.fields)
        if (type.fieldNamed(node.name.value) != null) node,
    ];
    final message =
        'Within OneOf Input Object type "${type.name}", exactly one field '
        'must be specified, and the value for that field must be non-null.';
    return switch (known) {
      [ObjectField(name: final name, value: NullValue())] => _report(
        message,
        value,
        _Path(path, name.value),
      ),
      [_] => null,
      _ => _report(message, value, path),
    };
  }

  static _Report _report(String message, Node node, _Path? path) =>
      _Report(ValueProblem(message, node, _Path.keys(path)));
}

sealed class _Work {}

final class _Check(
  final Value value,
  final TypeRef type,
  final _Path? path,
) extends _Work {
  this;
}

// A path shares its parent, so a deep value costs linear time; the list
// of keys is built only for a problem.
final class _Path(final _Path? parent, final Object key) {
  this;

  static List<Object> keys(_Path? path) {
    final keys = <Object>[];
    for (var current = path; current != null; current = current.parent) {
      keys.add(current.key);
    }
    return keys.reversed.toList();
  }
}

final class _Report(final ValueProblem problem) extends _Work {
  this;
}
