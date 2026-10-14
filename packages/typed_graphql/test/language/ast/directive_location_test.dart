import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('spells every location as the spec does', () {
    expect(DirectiveLocation.values.map((location) => location.spelling), [
      'QUERY',
      'MUTATION',
      'SUBSCRIPTION',
      'FIELD',
      'FRAGMENT_DEFINITION',
      'FRAGMENT_SPREAD',
      'INLINE_FRAGMENT',
      'VARIABLE_DEFINITION',
      'SCHEMA',
      'SCALAR',
      'OBJECT',
      'FIELD_DEFINITION',
      'ARGUMENT_DEFINITION',
      'INTERFACE',
      'UNION',
      'ENUM',
      'ENUM_VALUE',
      'INPUT_OBJECT',
      'INPUT_FIELD_DEFINITION',
      'DIRECTIVE_DEFINITION',
    ]);
  });

  test('finds a location by its spelling', () {
    expect(
      DirectiveLocation.named('INPUT_FIELD_DEFINITION'),
      DirectiveLocation.inputFieldDefinition,
    );
    expect(DirectiveLocation.named('ENUM'), DirectiveLocation.enumType);
  });

  test('finds nothing for another spelling', () {
    expect(DirectiveLocation.named('field'), isNull);
    expect(DirectiveLocation.named('FIELDS'), isNull);
  });

  test('the eight operation locations are executable', () {
    expect(
      DirectiveLocation.values.where((location) => location.isExecutable),
      [
        DirectiveLocation.query,
        DirectiveLocation.mutation,
        DirectiveLocation.subscription,
        DirectiveLocation.field,
        DirectiveLocation.fragmentDefinition,
        DirectiveLocation.fragmentSpread,
        DirectiveLocation.inlineFragment,
        DirectiveLocation.variableDefinition,
      ],
    );
  });
}
