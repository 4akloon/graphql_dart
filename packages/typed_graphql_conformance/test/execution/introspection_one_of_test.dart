@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Fields {
  const _Fields();
}

enum _OnlyEnum { someObject }

// Ported from the oneOf tests of graphql-js
// src/type/__tests__/introspection-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. graphql-js builds its schemas from
// SDL; these are built with the typed builder and have the same types.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldDef<Object?, Object?> someField(
    FieldsBuilder<Object?, Object?> t,
    OutputRef<Object?> type, {
    List<Arg<Object?>> args = const [],
    String name = 'someField',
  }) => t.field(name, type, args: args).resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  group('Introspection', () {
    test('identifies oneOf for input objects', () async {
      final b = builder();
      final someInput = b.oneOfInputObject<_Fields>(
        'SomeInputObject',
        fields: () => [Arg('a', b.string.nullable)],
        decode: (values) => const _Fields(),
      );
      final anotherInput = b.inputObject<_Fields>(
        'AnotherInputObject',
        fields: () => [
          Arg('a', b.string.nullable),
          Arg('b', b.string.nullable),
        ],
        decode: (values) => const _Fields(),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', someInput.nullable)],
            ),
            someField(
              t,
              b.string.nullable,
              args: [Arg('anotherArg', anotherInput.nullable)],
              name: 'anotherField',
            ),
          ],
        ),
      );

      const source = '''

      {
        oneOfInputObject: __type(name: "SomeInputObject") {
          isOneOf
        }
        inputObject: __type(name: "AnotherInputObject") {
          isOneOf
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'oneOfInputObject': {'isOneOf': true},
          'inputObject': {'isOneOf': false},
        },
      });
    });

    test('returns null for oneOf for other types', () async {
      final b = builder();
      final someEnum = b.enumType<_OnlyEnum>(
        'SomeEnum',
        _OnlyEnum.values,
        mapping: EnumValueMapping<_OnlyEnum>(nameOf: (value) => 'SomeObject'),
      );
      final someInterface = b.interface<Object?>(
        'SomeInterface',
        fields: (t) => [t.field('fieldA', b.string.nullable).declareOnly()],
      );
      final someObject = b.object<Object?>(
        'SomeObject',
        interfaces: [someInterface],
        fields: (t) => [someField(t, b.string.nullable, name: 'fieldA')],
      );
      final someUnion = b.union<Object?>(
        'SomeUnion',
        members: [someObject],
        resolveType: (value) => someObject,
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              someUnion.nullable,
              args: [Arg('enum', someEnum.nullable)],
            ),
            someField(
              t,
              someInterface.nullable,
              args: [Arg('enum', someEnum.nullable)],
              name: 'anotherField',
            ),
          ],
        ),
      );

      const source = '''

      {
        object: __type(name: "SomeObject") {
          isOneOf
        }
        enum: __type(name: "SomeEnum") {
          isOneOf
        }
        interface: __type(name: "SomeInterface") {
          isOneOf
        }
        scalar: __type(name: "String") {
          isOneOf
        }
        union: __type(name: "SomeUnion") {
          isOneOf
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'object': {'isOneOf': null},
          'enum': {'isOneOf': null},
          'interface': {'isOneOf': null},
          'scalar': {'isOneOf': null},
          'union': {'isOneOf': null},
        },
      });
    });
  });
}
