import '../../language/ast/type_ref.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rule that every input object type can be given a finite value
/// (spec §3.10.1 `InputObjectHasUnbreakableCycle`), as graphql-js's
/// `detectInputObjectNonFiniteValues`: the types known to have a finite
/// value are propagated through the reverse edges in one pass, then each
/// cycle among the others is reported once, by a walk with its own stack.
final class FiniteValueRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every input object type that cannot be given a finite value.
  void check() {
    // A repeated name, which only a schema built in code holds, keeps the
    // first type, as Schema.typeNamed does.
    final states = <String, _State>{};
    for (final type in schema.types.whereType<InputObjectType>()) {
      states.putIfAbsent(type.name, () => _State(type));
    }
    final finite = <_State>[];
    for (final state in states.values) {
      _link(state, states, finite);
    }
    while (finite.isNotEmpty) {
      for (final dependent in finite.removeLast().dependents) {
        if (dependent.hasFiniteValue) continue;
        dependent.unresolved--;
        if (dependent.type.isOneOf || dependent.unresolved == 0) {
          _mark(dependent, finite);
        }
      }
    }
    _CycleReport(report, states).run();
  }

  // A non-null field of an input object type must be given a value; a
  // OneOf type is given one field, so any nullable input object field.
  void _link(_State state, Map<String, _State> states, List<_State> finite) {
    final fields = state.type.fields;
    for (final field in fields) {
      if (states[_targetName(state.type, field.type)] case final target?) {
        state.targets.add((field, target));
        target.dependents.add(state);
      }
    }
    state.unresolved = state.targets.length;
    if (state.type.isOneOf
        ? fields.isEmpty || state.targets.length < fields.length
        : state.targets.isEmpty) {
      _mark(state, finite);
    }
  }

  String? _targetName(InputObjectType type, TypeRef fieldType) =>
      switch ((type.isOneOf, fieldType)) {
        (true, NamedType(:final name)) => name.value,
        (false, NonNullType(type: NamedType(:final name))) => name.value,
        _ => null,
      };

  static void _mark(_State state, List<_State> finite) {
    if (state.hasFiniteValue) return;
    state.hasFiniteValue = true;
    finite.add(state);
  }
}

// The propagation state of one input object type.
final class _State(final InputObjectType type) {
  this;

  final List<(InputValue, _State)> targets = [];
  final List<_State> dependents = [];
  int unresolved = 0;
  bool hasFiniteValue = false;
}

// graphql-js's reportCycleRecursive, with a stack of frames: the path of
// fields walked, and the position in it where each walked type entered.
final class _CycleReport(
  final ValidationReport report,
  final Map<String, _State> states,
) {
  this;

  final Set<_State> _visited = {};
  final List<_Frame> _frames = [];
  final List<(String, InputValue)> _path = [];
  final Map<_State, int> _positions = {};

  void run() {
    for (final state in states.values) {
      if (!state.hasFiniteValue && !_visited.contains(state)) _walk(state);
    }
  }

  void _walk(_State root) {
    _enter(root);
    while (_frames.isNotEmpty) {
      final frame = _frames.last;
      if (frame.next == frame.state.targets.length) {
        _frames.removeLast();
        _positions.remove(frame.state);
        if (_frames.isNotEmpty) _path.removeLast();
        continue;
      }
      final (field, target) = frame.state.targets[frame.next++];
      if (target.hasFiniteValue) continue;
      _path.add(('${frame.state.type.name}.${field.name}', field));
      if (_positions[target] case final position?) {
        _report(target, position);
        _path.removeLast();
      } else if (_visited.contains(target)) {
        _path.removeLast();
      } else {
        _enter(target);
      }
    }
  }

  void _enter(_State state) {
    _visited.add(state);
    _positions[state] = _path.length;
    _frames.add(_Frame(state));
  }

  void _report(_State target, int position) {
    final cycle = _path.sublist(position);
    report.error(
      .infiniteInputValue,
      'Input Object ${target.type.name} cannot be provided a finite value '
      'because it references itself through fields: '
      '${[for (final (name, _) in cycle) name].join(', ')}.',
      [for (final (_, field) in cycle) field.span],
    );
  }
}

// A type being walked and the index of its next target.
final class _Frame(final _State state) {
  this;

  int next = 0;
}
