import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/validation-test.ts;
// mapping/validation.csv says which tests are adapted, and why.
void main() {
  final specified = RulePort.all(DocumentValidator.specifiedRules);

  group('Validate: Supports full validation', () {
    test('validates queries', () {
      expect(
        specified.errors('''
      query {
        human {
          pets {
            ... on Cat {
              meowsVolume
            }
            ... on Dog {
              barkVolume
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('detects unknown fields', () {
      expect(
        specified.errors('''
      {
        unknown
      }
    '''),
        ['Cannot query field "unknown" on type "QueryRoot". @ 3:9'],
      );
    });

    test('validates using a custom rule', () {
      final port = RulePort(const _ReportDirectiveRule()).withSchema('''
      directive @custom(arg: String) on FIELD

      type Query {
        foo: String
      }
    ''');
      expect(
        port.errors('''
      query {
        name @custom
      }
    '''),
        ['Reporting directive: @custom @ 3:14'],
      );
    });
  });

  group('Validate: Limit maximum number of validation errors', () {
    final document = const Parser()
        .parse(
          Source('''
    {
      firstUnknownField
      secondUnknownField
      thirdUnknownField
    }
  '''),
        )
        .requireDocument();

    List<String> messages(int maxErrors) => [
      for (final diagnostic in DocumentValidator(
        maxErrors: maxErrors,
      ).validate(RulePort.testSchema, document).diagnostics)
        diagnostic.message,
    ];

    String invalidField(String name) =>
        'Cannot query field "$name" on type "QueryRoot".';

    test('when maxErrors is equal to number of errors', () {
      expect(messages(3), [
        invalidField('firstUnknownField'),
        invalidField('secondUnknownField'),
        invalidField('thirdUnknownField'),
      ]);
    });

    test('when maxErrors is less than number of errors', () {
      // Adapted: the limit is the sink's GQL000, with its own message.
      expect(messages(2), [
        invalidField('firstUnknownField'),
        invalidField('secondUnknownField'),
        'Too many errors: the limit of 2 was reached and the rest are not '
            'reported.',
      ]);
    });

    test('passthrough exceptions from rules', () {
      expect(
        () => const DocumentValidator(
          rules: [_ThrowingRule()],
          maxErrors: 1,
        ).validate(RulePort.testSchema, document),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Error from custom rule!',
          ),
        ),
      );
    });
  });

  group('operation and variable definition descriptions', () {
    test('validates operation with description and variable descriptions', () {
      final port = RulePort.all(
        DocumentValidator.specifiedRules,
      ).withSchema('type Query { field(a: Int, b: String): String }');
      expect(
        port.errors(r'''
        "Operation description"
        query myQuery(
          "Variable a description"
          $a: Int,
          """Variable b\nmultiline description"""
          $b: String
        ) {
          field(a: $a, b: $b)
        }
      '''),
        isEmpty,
      );
    });
  });
}

/// graphql-js's `customRule` that reports each directive it enters.
final class _ReportDirectiveRule extends ValidationRule {
  const _ReportDirectiveRule();

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ReportDirective(context);
}

final class _ReportDirective extends AstVisitor {
  _ReportDirective(this.context);

  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    if (node is Directive) {
      context.report(
        DiagnosticCode.customRuleViolation,
        'Reporting directive: @${context.typeInfo.directive?.name}',
        [node],
      );
    }
    return VisitAction.next;
  }
}

/// graphql-js's rule that throws from its `Field` visitor.
final class _ThrowingRule extends ValidationRule {
  const _ThrowingRule();

  @override
  AstVisitor createVisitor(ValidationContext context) => _Throwing();
}

final class _Throwing extends AstVisitor {
  @override
  VisitAction enter(Node node) => switch (node) {
    Field() => throw StateError('Error from custom rule!'),
    _ => VisitAction.next,
  };
}
