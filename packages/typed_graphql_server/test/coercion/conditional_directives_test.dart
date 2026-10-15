import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/conditional_directives.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  final directives = ConditionalDirectives(fx.environment);

  CoercionResult run(
    String written, [
    Map<String, Object?> variables = const {},
  ]) {
    final operation =
        const Parser()
                .parse(Source('{ a$written }'))
                .requireDocument()
                .definitions
                .single
            as OperationDefinition;
    final field = operation.selectionSet.selections.single as Field;
    return directives.isIncluded(field.directives, variables);
  }

  Object? includedOf(
    String written, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(written, variables)) {
    CoercionSuccess(:final value) => value,
    CoercionFailure(:final problems) => fail(problems.single.message),
  };

  String messageOf(String written) => switch (run(written)) {
    CoercionSuccess() => fail('expected a failure'),
    CoercionFailure(:final problems) => problems.single.message,
  };

  test('includes a selection without directives', () {
    expect(includedOf(''), isTrue);
  });

  test('skips on @skip(if: true)', () {
    expect(includedOf(' @skip(if: true)'), isFalse);
  });

  test('keeps on @skip(if: false)', () {
    expect(includedOf(' @skip(if: false)'), isTrue);
  });

  test('keeps on @include(if: true)', () {
    expect(includedOf(' @include(if: true)'), isTrue);
  });

  test('drops on @include(if: false)', () {
    expect(includedOf(' @include(if: false)'), isFalse);
  });

  test('reads the condition from a variable', () {
    expect(includedOf(r' @skip(if: $s)', {'s': true}), isFalse);
  });

  test('lets @skip win over @include', () {
    expect(includedOf(' @include(if: true) @skip(if: true)'), isFalse);
  });

  test('reports an if argument that is not a Boolean', () {
    expect(
      messageOf(' @skip(if: 1)'),
      'Argument "@skip(if:)" has invalid value: Boolean cannot represent a '
      'non boolean value: 1',
    );
  });

  test('reports a missing if argument', () {
    expect(
      messageOf(' @include'),
      'Argument "@include(if:)" of required type "Boolean!" was not '
      'provided.',
    );
  });

  test('reports a variable without a value', () {
    expect(
      messageOf(r' @skip(if: $s)'),
      'Argument "@skip(if:)" has invalid value: Expected variable '
      r'"$s" provided to type "Boolean!" to provide a runtime value.',
    );
  });
}
