import 'argument_text.dart';
import 'field_selection.dart';
import 'identity_key.dart';
import 'look_ahead_budget.dart';
import 'selected_field.dart';

/// Builds the canonical text of a [FieldSelection] with an explicit stack,
/// so a selection a thousand levels deep costs no call depth (R0.3).
///
/// Fields over the same field nodes are read once (their text is
/// remembered), and entries with the same text collapse to one, so aliases
/// that repeat a fragment cost nothing extra. What remains is charged to the
/// [LookAheadBudget] by the size of the text it builds, before it builds it.
final class SelectionFingerprint {
  /// Creates the builder.
  const SelectionFingerprint();

  /// The text of [root]: each field as `name(arguments)` and, when it has a
  /// sub-selection, `{children}`; siblings sorted, joined by commas and
  /// listed once when they read the same.
  String of(FieldSelection root, LookAheadBudget budget) {
    final done = <IdentityKey, _Entry>{};
    final stack = <_Level>[_Level(null, null, root.fields)];
    while (true) {
      final level = stack.last;
      if (level.next case final field?) {
        final known = done[field.key];
        if (known != null) {
          level.add(known);
          continue;
        }
        final text = '${field.name}${const ArgumentText().of(field.arguments)}';
        final children = field.selection.fields;
        if (children.isEmpty) {
          budget.charge(1);
          level.add(done[field.key] = (text: text, size: 1));
        } else {
          stack.add(_Level(field.key, text, children));
        }
        continue;
      }
      stack.removeLast();
      final entry = level.finish(budget);
      final key = level.key;
      if (key == null) {
        return entry.text;
      }
      stack.last.add(done[key] = entry);
    }
  }
}

// The text of a finished field and the number of fields that text holds.
typedef _Entry = ({String text, int size});

// One selection being read: the key and text of the field that owns it (null
// for the root), its fields still to read and the distinct entries so far.
final class _Level {
  _Level(this.key, this._prefix, this._fields);

  final IdentityKey? key;
  final String? _prefix;
  final List<SelectedField> _fields;
  final Map<String, int> _entries = {};
  int _index = 0;

  SelectedField? get next => _index < _fields.length ? _fields[_index++] : null;

  void add(_Entry entry) => _entries[entry.text] = entry.size;

  _Entry finish(LookAheadBudget budget) {
    var size = _prefix == null ? 0 : 1;
    for (final entrySize in _entries.values) {
      size += entrySize;
    }
    budget.charge(size);
    final joined = (_entries.keys.toList()..sort()).join(',');
    return (
      text: _prefix == null ? joined : '$_prefix{$joined}',
      size: size,
    );
  }
}
