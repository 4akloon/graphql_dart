import 'package:typed_graphql/typed_graphql.dart';

/// A visitor that writes each call to [entries], as `enter Field b` or
/// `leave Name b`, after its [label]; it skips or stops at the node whose
/// description is [skipAt] or [stopAt].
final class VisitLog extends AstVisitor {
  /// Creates a log that writes to [entries].
  VisitLog(this.entries, {this.label = '', this.skipAt, this.stopAt});

  /// Where the calls are written, in call order.
  final List<String> entries;

  /// Written before each entry, such as `no-a `; empty by default.
  final String label;

  /// The description of the node [enter] skips.
  final String? skipAt;

  /// The description of the node [enter] stops at.
  final String? stopAt;

  @override
  VisitAction enter(Node node) {
    final description = describe(node);
    entries.add('${label}enter $description');
    if (description == stopAt) {
      return VisitAction.stop;
    }
    return description == skipAt ? VisitAction.skip : VisitAction.next;
  }

  @override
  void leave(Node node) => entries.add('${label}leave ${describe(node)}');

  /// [node] as an entry names it: its kind, and the name of a field or
  /// the value of a name or a number.
  static String describe(Node node) => switch (node) {
    Name(:final value) => 'Name $value',
    Field(:final name) => 'Field ${name.value}',
    IntValue(:final value) => 'IntValue $value',
    Document() => 'Document',
    OperationDefinition() => 'OperationDefinition',
    SelectionSet() => 'SelectionSet',
    Argument() => 'Argument',
    ListValue() => 'ListValue',
    _ => 'Node',
  };
}
