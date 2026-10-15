import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/condition.dart';
import 'package:typed_graphql_codegen/src/plan/directive_conditions.dart';

void main() {
  List<Condition>? read(String directives) {
    final document = const Parser()
        .parse(
          Source(
            r'query ($v: Boolean!, $w: Boolean!) { a '
            '$directives }',
          ),
        )
        .requireDocument();
    final field =
        (document.definitions.single as OperationDefinition)
                .selectionSet
                .selections
                .single
            as Field;
    return const DirectiveConditions().of(field.directives);
  }

  test('no directive adds nothing', () {
    expect(read(''), <Condition>[]);
  });

  test('include(if: false) excludes the selection', () {
    expect(read('@include(if: false)'), isNull);
  });

  test('include(if: true) adds nothing', () {
    expect(read('@include(if: true)'), <Condition>[]);
  });

  test('skip(if: true) excludes the selection', () {
    expect(read('@skip(if: true)'), isNull);
  });

  test('skip(if: false) adds nothing', () {
    expect(read('@skip(if: false)'), <Condition>[]);
  });

  test(r'include(if: $v) is an include condition', () {
    expect(read(r'@include(if: $v)'), [const Condition('v', true)]);
  });

  test(r'skip(if: $v) is a skip condition', () {
    expect(read(r'@skip(if: $v)'), [const Condition('v', false)]);
  });

  test('two variable directives keep their order', () {
    expect(read(r'@skip(if: $w) @include(if: $v)'), [
      const Condition('w', false),
      const Condition('v', true),
    ]);
  });

  test('a literal that excludes wins over a variable', () {
    expect(read(r'@include(if: $v) @skip(if: true)'), isNull);
  });

  test('another directive is ignored', () {
    expect(read('@other'), <Condition>[]);
  });

  test('a condition prints with a bang for skip', () {
    expect(
      [const Condition('v', true), const Condition('v', false)].join(' '),
      r'$v !$v',
    );
  });
}
