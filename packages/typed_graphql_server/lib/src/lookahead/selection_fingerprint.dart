import 'argument_text.dart';
import 'field_selection.dart';
import 'selected_field.dart';

/// Builds the canonical text of a [FieldSelection] with an explicit stack,
/// so a selection a thousand levels deep costs no call depth (R0.3).
final class SelectionFingerprint {
  /// Creates the builder.
  const SelectionFingerprint();

  /// The text of [root]: each field as `name(arguments)` and, when it has a
  /// sub-selection, `{children}`; siblings sorted and joined by commas.
  String of(FieldSelection root) {
    final stack = <_Level>[_Level('', root.fields)];
    while (true) {
      final level = stack.last;
      if (level.next case final field?) {
        final text = '${field.name}${const ArgumentText().of(field.arguments)}';
        final children = field.selection.fields;
        if (children.isEmpty) {
          level.entries.add(text);
        } else {
          stack.add(_Level(text, children));
        }
        continue;
      }
      stack.removeLast();
      final joined = (level.entries..sort()).join(',');
      if (stack.isEmpty) {
        return joined;
      }
      stack.last.entries.add('${level.prefix}{$joined}');
    }
  }
}

// One selection being read: the text of the field that owns it, its fields
// still to read and the entries finished so far.
final class _Level {
  _Level(this.prefix, this._fields);

  final String prefix;
  final List<SelectedField> _fields;
  final List<String> entries = [];
  int _index = 0;

  SelectedField? get next => _index < _fields.length ? _fields[_index++] : null;
}
