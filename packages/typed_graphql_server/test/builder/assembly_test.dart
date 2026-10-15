import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/possible_types.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Box {
  const Box();
}

final class PickyCodec implements ScalarCodec<Box> {
  const PickyCodec();

  @override
  DecodeResult<Box> decode(JsonValue json) => const DecodeSuccess(Box());

  @override
  JsonValue encode(Box value) =>
      throw ArgumentError.value(value, 'box', 'Not writable');
}

void main() {
  late ExecutableSchemaBuilder<Object?> b;

  setUp(() => b = ExecutableSchemaBuilder<Object?>());

  List<Diagnostic> problemsOf(void Function() build) {
    Object? thrown;
    try {
      build();
    } on Object catch (error) {
      thrown = error;
    }
    if (thrown case SchemaBuildError(:final diagnostics)) return diagnostics;
    fail('build did not throw a SchemaBuildError: $thrown');
  }

  ObjectTypeDef<Object?> queryOf(
    List<FieldDef<Object?, Object?>> Function(
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  String sdlOf(ObjectTypeDef<Object?> query) {
    final tag = SchemaDirective(
      'tag',
      locations: const [
        DirectiveLocation.fieldDefinition,
        DirectiveLocation.object,
      ],
    );
    final built = b.build(
      query: query,
      options: BuildOptions(directives: [tag]),
    );
    return const SchemaPrinter().print(built.schema.schema);
  }

  group('default values', () {
    test('a bad default on an inherited interface field is reported once', () {
      final picky = b.scalar<Box>('Picky', const PickyCodec());
      final node = b.interface<Object?>(
        'Node',
        fields: (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', picky, defaultValue: const Box())],
              )
              .resolve((parent, args, context, info) => true),
        ],
      );
      b.object<Object?>('First', interfaces: [node], fields: (t) => []);
      b.object<Object?>('Second', interfaces: [node], fields: (t) => []);
      final query = queryOf(
        (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(
        problems.where(
          (problem) => problem.code == DiagnosticCode.unencodableDefaultValue,
        ),
        hasLength(1),
      );
    });

    test('the reason keeps the value and name of an ArgumentError.value', () {
      final picky = b.scalar<Box>('Picky', const PickyCodec());
      final query = queryOf(
        (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', picky, defaultValue: const Box())],
              )
              .resolve((parent, args, context, info) => true),
        ],
      );
      final message = problemsOf(() => b.build(query: query)).single.message;
      expect(message, contains('Not writable'));
      expect(message, contains('"box"'));
      expect(message, contains("Instance of 'Box'"));
    });
  });

  group('directives', () {
    test('withDirectives on a field is printed', () {
      final query = queryOf(
        (t) => [
          t
              .field('ok', b.boolean)
              .withDirectives([AppliedDirective('tag')])
              .pure((_) => true),
        ],
      );
      expect(sdlOf(query), contains('ok: Boolean! @tag'));
    });

    test('ObjectOptions.directives on a type is printed', () {
      final query = b.object<Object?>(
        'Query',
        options: ObjectOptions(directives: [AppliedDirective('tag')]),
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      expect(sdlOf(query), contains('type Query @tag'));
    });
  });

  group('roots', () {
    test('a Subscription object type becomes the subscription root', () {
      final query = queryOf(
        (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [t.field('ticks', b.int).pure((_) => 1)],
      );
      final schema = b
          .build(query: query, subscription: subscription)
          .schema
          .schema;
      expect(schema.subscriptionTypeName, 'Subscription');
      expect(schema.typeNamed('Subscription'), isA<ObjectType>());
    });
  });

  group('PossibleTypes', () {
    test('counts the interfaces an object lists, not those they list', () {
      final node = b.interface<Object?>(
        'Node',
        fields: (t) => [t.field('id', b.id).declareOnly()],
      );
      final entity = b.interface<Object?>(
        'Entity',
        interfaces: [node],
        fields: (t) => [t.field('id', b.id).declareOnly()],
      );
      final thing = b.object<Object?>(
        'Thing',
        interfaces: [entity],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final possible = PossibleTypes(b.definitions);
      expect(possible.of(entity), [thing]);
      expect(possible.of(node), isEmpty);
    });
  });
}
