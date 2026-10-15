import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

/// Runs [onEnter] at each node and [onLeave] when the walk leaves the
/// document.
final class _Probe extends ValidationRule {
  const _Probe({this.onEnter, this.onLeave});

  final void Function(ValidationContext context, Node node)? onEnter;
  final void Function(ValidationContext context)? onLeave;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ProbeVisitor(this, context);
}

final class _ProbeVisitor extends AstVisitor {
  _ProbeVisitor(this.probe, this.context);

  final _Probe probe;
  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    probe.onEnter?.call(context, node);
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    if (node is Document) {
      probe.onLeave?.call(context);
    }
  }
}

void main() {
  final checked = Checked('''
type Query { name: String friend: Query }
''');
  final fieldsReported = _Probe(
    onEnter: (context, node) {
      if (node is Field) {
        context.report(
          DiagnosticCode.customRuleViolation,
          'field ${node.name.value}',
          [node, node.name],
        );
      }
    },
  );

  test('a document no rule reports is valid and bound to the schema', () {
    final result = checked.validate('{ name }');
    expect(result, isA<ValidDocument>());
    expect(result.schema, same(checked.schema));
    expect(result.diagnostics, isEmpty);
  });

  test('a report points at the first node and relates the others', () {
    final result = checked.validate(
      '{ name }',
      validator: DocumentValidator(rules: [fieldsReported]),
    );
    final diagnostic = (result as InvalidDocument).diagnostics.single;
    expect(diagnostic.code, DiagnosticCode.customRuleViolation);
    expect(diagnostic.span?.text, 'name');
    expect(diagnostic.span?.location, const SourceLocation(1, 3));
    expect(diagnostic.related, hasLength(1));
  });

  test('without a source a report has no span', () {
    final document = const Parser().parse(Source('{ name }')).requireDocument();
    final result = DocumentValidator(
      rules: [fieldsReported],
    ).validate(checked.schema, document);
    expect(result.diagnostics.single.span, isNull);
  });

  test('the error limit stops the walk with GQL000', () {
    var fieldsSeen = 0;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is Field) {
          fieldsSeen++;
          context.report(DiagnosticCode.customRuleViolation, 'field', [node]);
        }
      },
    );
    final result = checked.validate(
      '{ name name name name }',
      validator: DocumentValidator(rules: [rule], maxErrors: 2),
    );
    expect(result.diagnostics.map((diagnostic) => diagnostic.code.id), [
      'GQL231',
      'GQL231',
      'GQL000',
    ]);
    expect(fieldsSeen, 3);
  });

  test('spending past the budget reports GQL230 once and stops', () {
    var fieldsSeen = 0;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is Field) {
          fieldsSeen++;
          context.spend(10);
        }
      },
    );
    final result = checked.validate(
      '{ name name name name }',
      validator: DocumentValidator(rules: [rule], maxSteps: 15),
    );
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, DiagnosticCode.documentTooComplex);
    expect(diagnostic.span?.text, '{ name name name name }');
    expect(fieldsSeen, 2);
  });

  test('includesSuggestions reaches the context', () {
    bool? seen;
    final rule = _Probe(
      onLeave: (context) => seen = context.includesSuggestions,
    );
    checked.validate(
      '{ name }',
      validator: DocumentValidator(rules: [rule], includesSuggestions: false),
    );
    expect(seen, isFalse);
  });

  test('usage queries throw before the walk has left the document', () {
    var isChecked = false;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is OperationDefinition) {
          expect(() => context.variableUsagesOf(node), throwsStateError);
          isChecked = true;
        }
      },
    );
    checked.validate('{ name }', validator: DocumentValidator(rules: [rule]));
    expect(isChecked, isTrue);
  });

  test('variable usages are collected through fragments, each once', () {
    final lines = <String>[];
    final rule = _Probe(
      onLeave: (context) {
        for (final definition in context.document.definitions) {
          if (definition is! OperationDefinition) {
            continue;
          }
          final fragments = context.recursivelyReferencedFragments(definition);
          final usages = context.recursiveVariableUsages(definition);
          lines
            ..add(fragments.map((fragment) => fragment.name.value).join(' '))
            ..add(usages.map((usage) => usage.node.name.value).join(' '));
        }
      },
    );
    checked.validate(r'''
query Q($a: String) { ...A friend { ...B } }
fragment A on Query { ...B ...A name @include(if: $a) }
fragment B on Query { friend { ...A name @skip(if: $b) } }
''', validator: DocumentValidator(rules: [rule]));
    expect(lines, ['A B', 'a b']);
  });

  test('a variable usage knows its expected type and default', () {
    final lines = <String>[];
    final rule = _Probe(
      onLeave: (context) {
        final operation = context.document.definitions.single;
        for (final usage in context.variableUsagesOf(
          operation as OperationDefinition,
        )) {
          lines.add(
            '${usage.node.name.value} ${const Printer().print(usage.type!)}',
          );
        }
      },
    );
    checked.validate(
      r'query ($a: Boolean!) { name @include(if: $a) }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(lines, ['a Boolean!']);
  });

  test('a fragment name shared by two definitions means the last one', () {
    String? seen;
    final rule = _Probe(
      onLeave: (context) =>
          seen = context.fragmentNamed('F')?.typeCondition.name.value,
    );
    checked.validate(
      'fragment F on Query { name } fragment F on Missing { name }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(seen, 'Missing');
  });

  test('the walk does not enter descriptions', () {
    final strings = <String>[];
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is StringValue) strings.add(node.value);
      },
    );
    checked.validate(
      r'"o" query Q("v" $a: String = "d") { name } '
      '"f" fragment F on Query { name }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(strings, ['d']);
  });

  test('the specified rules are the 30 rules of spec §5, each once', () {
    final kinds = {
      for (final rule in DocumentValidator.specifiedRules) rule.runtimeType,
    };
    expect(kinds, hasLength(30));
    expect(DocumentValidator.specifiedRules, hasLength(30));
  });
}
