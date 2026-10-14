import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  group('NodeSpans', () {
    test('gives the span of a node in the source', () {
      final source = Source('type Query');
      final span = NodeSpans(source).of(const Name('Query', start: 5, end: 10));
      expect(span, SourceSpan(source, 5, 10));
      expect(span?.text, 'Query');
    });

    test('gives no span without a source', () {
      expect(const NodeSpans(null).of(const Name('Query')), isNull);
    });
  });

  group('ElementReader', () {
    final sdl = Sdl('''
type Query {
  "The hero"
  hero(episode: Episode = JEDI @deprecated, limit: [Int!]): Character @auth(role: "x")
}

enum Episode {
  """Star Wars"""
  NEWHOPE @deprecated(reason: "old")
}

"Marks a field"
directive @auth(role: String) repeatable on FIELD_DEFINITION | OBJECT
''');
    final reader = ElementReader(NodeSpans(sdl.source));
    final type = sdl.all<ObjectTypeDefinition>().single;
    final field = reader.field(type.fields.single);

    test('reads a field with its description, type and arguments', () {
      expect(field.name, 'hero');
      expect(field.description, 'The hero');
      expect(const Printer().print(field.type), 'Character');
      expect(field.arguments.map((argument) => argument.name), [
        'episode',
        'limit',
      ]);
      expect(const Printer().print(field.arguments[1].type), '[Int!]');
    });

    test('keeps a default value as its language node', () {
      final defaultValue = field.arguments.first.defaultValue;
      expect(defaultValue, isA<EnumValue>());
      expect(const Printer().print(defaultValue!), 'JEDI');
      expect(field.arguments[1].defaultValue, isNull);
    });

    test('reads applied directives with their arguments', () {
      expect(field.appliedDirectives.single.name, 'auth');
      expect(
        field.appliedDirectives.single.argument('role'),
        isA<StringValue>(),
      );
      expect(field.arguments.first.deprecationReason, 'No longer supported');
    });

    test('gives every element the span of its node', () {
      expect(field.span?.text, startsWith('"The hero"\n  hero('));
      expect(field.span?.text, endsWith('@auth(role: "x")'));
      expect(
        field.arguments.first.span?.text,
        'episode: Episode = JEDI '
        '@deprecated',
      );
      expect(field.appliedDirectives.single.span?.text, '@auth(role: "x")');
    });

    test('reads an enum value', () {
      final node = sdl.all<EnumTypeDefinition>().single.values.single;
      final value = reader.enumValue(node);
      expect(value.name, 'NEWHOPE');
      expect(value.description, 'Star Wars');
      expect(value.deprecationReason, 'old');
    });

    test('reads a directive definition', () {
      final node = sdl.all<DirectiveDefinition>().single;
      final directive = reader.directive(node);
      expect(directive.name, 'auth');
      expect(directive.description, 'Marks a field');
      expect(directive.isRepeatable, isTrue);
      expect(directive.locations, ['FIELD_DEFINITION', 'OBJECT']);
      expect(directive.arguments.single.name, 'role');
      expect(directive.span?.location, const SourceLocation(11, 1));
    });

    test('gives no spans without a source', () {
      const reader = ElementReader(NodeSpans(null));
      final field = reader.field(type.fields.single);
      expect(field.span, isNull);
      expect(field.arguments.first.span, isNull);
    });
  });
}
