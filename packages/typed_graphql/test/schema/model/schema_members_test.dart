import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  AppliedDirective deprecated([Value? reason]) => AppliedDirective(
    'deprecated',
    arguments: [
      ?reason == null ? null : Argument(const Name('reason'), reason),
    ],
  );

  group('AppliedDirective', () {
    test('finds the first argument of a name', () {
      final directive = AppliedDirective(
        'd',
        arguments: [
          const Argument(Name('a'), IntValue('1')),
          const Argument(Name('a'), IntValue('2')),
        ],
      );
      expect(directive.argument('a'), isA<IntValue>());
      expect((directive.argument('a')! as IntValue).value, '1');
      expect(directive.argument('b'), isNull);
    });

    test('keeps its arguments unmodifiable', () {
      final directive = AppliedDirective('d', arguments: []);
      expect(
        () => directive.arguments.add(const Argument(Name('a'), NullValue())),
        throwsUnsupportedError,
      );
    });
  });

  group('deprecationReason', () {
    test('is null without @deprecated', () {
      const type = NamedType(Name('String'));
      expect(SchemaField('f', type).deprecationReason, isNull);
    });

    test('is the default reason for a bare @deprecated', () {
      final value = SchemaEnumValue('A', appliedDirectives: [deprecated()]);
      expect(value.deprecationReason, 'No longer supported');
    });

    test('is the reason string when one is given', () {
      final argument = InputValue(
        'a',
        const NamedType(Name('Int')),
        appliedDirectives: [deprecated(const StringValue('Use b.'))],
      );
      expect(argument.deprecationReason, 'Use b.');
    });

    test('reads a reason that is not a string as the default', () {
      final field = SchemaField(
        'f',
        const NamedType(Name('String')),
        appliedDirectives: [deprecated(const IntValue('1'))],
      );
      expect(field.deprecationReason, 'No longer supported');
    });

    test('reads the first of two @deprecated', () {
      final directive = SchemaDirective(
        'd',
        locations: [.field],
        appliedDirectives: [
          deprecated(const StringValue('first')),
          deprecated(const StringValue('second')),
        ],
      );
      expect(directive.deprecationReason, 'first');
    });
  });

  group('argumentNamed', () {
    final arguments = [
      InputValue('a', const NamedType(Name('Int'))),
      InputValue('b', const NamedType(Name('String'))),
    ];

    test('finds a field argument by name', () {
      final field = SchemaField(
        'f',
        const NamedType(Name('String')),
        arguments: arguments,
      );
      expect(field.argumentNamed('b'), same(arguments[1]));
      expect(field.argumentNamed('c'), isNull);
    });

    test('finds a directive argument by name', () {
      final directive = SchemaDirective('d', arguments: arguments);
      expect(directive.argumentNamed('a'), same(arguments[0]));
      expect(directive.argumentNamed('c'), isNull);
    });
  });

  test('a directive definition is not repeatable by default', () {
    final directive = SchemaDirective(
      'd',
      locations: [.field, .query],
    );
    expect(directive.isRepeatable, isFalse);
    expect(directive.locations, [
      DirectiveLocation.field,
      DirectiveLocation.query,
    ]);
  });

  test('an input value keeps its default value node', () {
    final value = ListValue(const [IntValue('1')]);
    final input = InputValue(
      'a',
      const ListType(NamedType(Name('Int'))),
      defaultValue: value,
    );
    expect(input.defaultValue, same(value));
  });

  test('the lists of a field and a directive cannot be modified', () {
    final field = SchemaField('f', const NamedType(Name('String')));
    final directive = SchemaDirective('d', locations: [.field]);
    expect(
      () => field.arguments.add(InputValue('a', field.type)),
      throwsUnsupportedError,
    );
    expect(
      () => field.appliedDirectives.add(AppliedDirective('x')),
      throwsUnsupportedError,
    );
    expect(() => directive.locations.add(.query), throwsUnsupportedError);
  });

  test('an element does not see the list it was built from change', () {
    final locations = [DirectiveLocation.field];
    final directive = SchemaDirective('d', locations: locations);
    locations.add(.query);
    expect(directive.locations, [DirectiveLocation.field]);
  });

  test('an element keeps its description and span', () {
    final span = SourceSpan(Source('f'), 0, 1);
    final field = SchemaField(
      'f',
      const NamedType(Name('String')),
      description: 'A field.',
      span: span,
    );
    expect(field.description, 'A field.');
    expect(field.span, same(span));
  });
}
