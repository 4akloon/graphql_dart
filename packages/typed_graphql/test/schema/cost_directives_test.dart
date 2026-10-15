import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

const _sdl = '''
type Query {
  items(first: Int @cost(weight: "1")): [Item!] @listSize(assumedSize: 10)
}

type Item @cost(weight: "2") {
  id: ID
}
''';

const _builder = SchemaBuilder(includesCostDirectives: true);

void main() {
  test('treats @cost as an unknown directive without the flag', () {
    final schema = Built(_sdl).schema;
    final result = const SchemaValidator().validate(schema);
    expect(result, isA<InvalidSchema>());
    expect(
      (result as InvalidSchema).diagnostics.map((d) => d.code),
      everyElement(DiagnosticCode.unknownDirective),
    );
    expect(schema.directiveNamed('cost'), isNull);
  });

  test('builds and validates a schema with both directives', () {
    final schema = Built(_sdl, builder: _builder).schema;
    expect(schema.includesCostDirectives, isTrue);
    expect(const SchemaValidator().validate(schema), isA<ValidSchema>());
  });

  test('finds the definitions by name only with the flag', () {
    final schema = Schema(includesCostDirectives: true);
    expect(schema.directiveNamed('cost'), isNotNull);
    expect(schema.directiveNamed('listSize')?.arguments, hasLength(4));
    expect(Schema().directiveNamed('listSize'), isNull);
  });

  test('prints the two definitions among the built-ins', () {
    final text = const SchemaPrinter(
      includesBuiltIns: true,
    ).print(Schema(includesCostDirectives: true));
    expect(
      text,
      contains(
        'directive @cost(\n'
        '  """The weight, a decimal number written as a string."""\n'
        '  weight: String!\n'
        ') on ARGUMENT_DEFINITION | ENUM | FIELD_DEFINITION | '
        'INPUT_FIELD_DEFINITION | OBJECT | SCALAR',
      ),
    );
    expect(text, contains('requireOneSlicingArgument: Boolean = true'));
    expect(text, contains(') on FIELD_DEFINITION'));
    expect(
      const SchemaPrinter(includesBuiltIns: true).print(Schema()),
      isNot(contains('@cost')),
    );
  });

  test('rejects a redefined @cost only with the flag', () {
    const sdl = 'directive @cost(weight: String!) on OBJECT';
    expect(Built(sdl).schema.directives.single.name, 'cost');
    expect(Built(sdl, builder: _builder).errors, [
      '1:12 GQL103 The built-in directive "@cost" cannot be redefined.',
    ]);
  });

  test('keeps the flag when extending a schema', () {
    final base = Schema(includesCostDirectives: true);
    final built = Built.extending(base, 'directive @listSize on FIELD');
    expect(built.errors.single, contains('GQL103'));
    expect(built.partial.includesCostDirectives, isTrue);
    final extended = Built.extending(base, 'type Query { a: Int }').schema;
    expect(extended.includesCostDirectives, isTrue);
  });

  test('writes the directives to introspection and reads the flag back', () {
    final schema = Built(_sdl, builder: _builder).schema;
    final json = schema.toIntrospection().toJson();
    final root = json['__schema']! as Map<String, Object?>;
    final directives = (root['directives']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      directives.map((directive) => directive['name']),
      containsAll(['cost', 'listSize']),
    );
    final value = switch (const JsonReader().read(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => fail('not JSON'),
    };
    final result = const SchemaBuilder().fromIntrospection(value);
    final rebuilt = (result as BuildSuccess).schema;
    expect(rebuilt.includesCostDirectives, isTrue);
    expect(rebuilt.directives, isEmpty);
  });

  test('reads a foreign @cost directive as an ordinary directive', () {
    final json = Built(
      'directive @cost(rate: Int) on OBJECT\ntype Query { a: Int }',
    ).schema.toIntrospection().toJson();
    final value = switch (const JsonReader().read(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => fail('not JSON'),
    };
    final rebuilt =
        (const SchemaBuilder().fromIntrospection(value) as BuildSuccess).schema;
    expect(rebuilt.includesCostDirectives, isFalse);
    expect(rebuilt.directives.map((directive) => directive.name), ['cost']);
  });

  test('tells the cost directives as built-ins by the flag', () {
    const builtIns = BuiltIns();
    expect(
      builtIns.isBuiltInDirective(
        'cost',
        includesDeferAndStream: false,
        includesCostDirectives: true,
      ),
      isTrue,
    );
    expect(
      builtIns.isBuiltInDirective(
        'listSize',
        includesDeferAndStream: true,
        includesCostDirectives: false,
      ),
      isFalse,
    );
  });
}
