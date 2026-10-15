import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

base class Pet {
  const Pet();
}

final class Cat extends Pet {
  const Cat();
}

final class Plain {}

final class Named {}

final class Box {
  const Box();
}

void main() {
  late ExecutableSchemaBuilder<Object?> b;

  setUp(() => b = ExecutableSchemaBuilder<Object?>());

  ObjectTypeDef<Object?> queryWith(
    List<FieldDef<Object?, Object?>> Function(
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  ObjectTypeDef<Object?> anyQuery() => queryWith(
    (t) => [t.field('ok', b.boolean).pure((_) => true)],
  );

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

  List<DiagnosticCode> codesOf(void Function() build) => [
    for (final problem in problemsOf(build)) problem.code,
  ];

  group('GQL300', () {
    test('an object whose Dart type is not a subtype of the interface', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Plain>(
        'Thing',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.map((problem) => problem.message), [
        'Type "Thing" (Dart type Plain) cannot implement interface "Node": '
            'Plain is not a subtype of Named.',
      ]);
      expect(problems.single.code, DiagnosticCode.incompatibleImplementation);
    });

    test('an interface that lists an interface of an unrelated type', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.interface<Plain>(
        'Other',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        contains(DiagnosticCode.incompatibleImplementation),
      );
    });

    test('a subtype of the interface type is accepted', () {
      final pet = b.interface<Pet>(
        'Pet',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Cat>(
        'Kitty',
        interfaces: [pet],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(() => b.build(query: query), returnsNormally);
    });
  });

  group('GQL301', () {
    ObjectTypeDef<Pet> pet({bool hasTypeTest = false}) => b.object<Pet>(
      'Animal',
      options: ObjectOptions(isTypeOf: hasTypeTest ? (v) => v is Pet : null),
      fields: (t) => [t.field('id', b.id).pure((_) => '1')],
    );

    ObjectTypeDef<Cat> cat({bool hasTypeTest = false}) => b.object<Cat>(
      'Kitty',
      options: ObjectOptions(isTypeOf: hasTypeTest ? (v) => v is Cat : null),
      fields: (t) => [t.field('id', b.id).pure((_) => '1')],
    );

    test('members whose Dart types overlap, without a resolveType', () {
      final members = [pet(), cat()];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.ambiguousTypeResolution);
      expect(
        problems.single.message,
        'The possible types "Animal" (Dart type Pet) and "Kitty" (Dart type '
        'Cat) of "Either" have overlapping Dart types, so a value cannot be '
        'matched to one of them: give "Either" a resolveType, or give both '
        'types an isTypeOf.',
      );
    });

    test('an interface counts its implementations', () {
      final named = b.interface<Pet>(
        'Named',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      for (final name in ['A', 'B']) {
        b.object<Pet>(
          name,
          interfaces: [named],
          fields: (t) => [t.field('id', b.id).pure((_) => '1')],
        );
      }
      b.object<Cat>(
        'C',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        [DiagnosticCode.ambiguousTypeResolution],
      );
    });

    test('a resolveType settles it', () {
      final members = [pet(), cat()];
      b.union<Pet>('Either', members: members, resolveType: (_) => members[0]);
      final query = anyQuery();
      final binding = b.build(query: query).bindings.abstractTypes['Either']!;
      expect(binding.resolveType!(const Cat()), same(members[0]));
    });

    test('an isTypeOf on both types settles it', () {
      final members = [pet(hasTypeTest: true), cat(hasTypeTest: true)];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      expect(() => b.build(query: query), returnsNormally);
    });

    test('an isTypeOf on one type does not', () {
      final members = [pet(hasTypeTest: true), cat()];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        [DiagnosticCode.ambiguousTypeResolution],
      );
    });
  });

  group('GQL302', () {
    test('an input object default without encode names the coordinate', () {
      final box = b.inputObject<Box>(
        'BoxInput',
        fields: () => [Arg('size', b.int, defaultValue: 1)],
        decode: (_) => const Box(),
      );
      final query = queryWith(
        (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', box, defaultValue: const Box())],
              )
              .pure((_) => true),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.unencodableDefaultValue);
      expect(
        problems.single.message,
        'The default value of "Query.open(box:)" cannot be written as a '
        'literal: Input object "BoxInput" has no encode function, so a '
        'default value of this type cannot be written.',
      );
    });

    test('a default the codec rejects, on an input field', () {
      final box = b.inputObject<Box>(
        'BoxInput',
        fields: () => [Arg('size', b.int, defaultValue: 4294967296)],
        decode: (_) => const Box(),
      );
      final query = queryWith(
        (t) => [
          t.field('open', b.boolean, args: [Arg('box', box)]).pure((_) => true),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.unencodableDefaultValue);
      expect(problems.single.message, contains('"BoxInput.size"'));
    });
  });

  group('core validation', () {
    test('two types with one name come back in the error', () {
      b.object<Object?>(
        'User',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Object?>(
        'User',
        fields: (t) => [t.field('name', b.string).pure((_) => 'a')],
      );
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.message, contains('"User"'));
      expect(problems.single.code.id, startsWith('GQL1'));
    });

    test('a union without members is reported', () {
      b.union<Object?>('Empty', members: const []);
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.message, contains('Empty'));
    });

    test('builder problems come before the validator problems', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Plain>(
        'Thing',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.union<Object?>('Empty', members: const []);
      final query = anyQuery();
      final codes = codesOf(() => b.build(query: query));
      expect(codes.first, DiagnosticCode.incompatibleImplementation);
      expect(codes, hasLength(2));
    });
  });

  group('SchemaBuildError', () {
    test('lists one diagnostic per line', () {
      final error = SchemaBuildError([
        Diagnostic(DiagnosticCode.incompatibleImplementation, .error, 'one'),
        Diagnostic(DiagnosticCode.ambiguousTypeResolution, .error, 'two'),
      ]);
      expect(
        error.toString(),
        'SchemaBuildError:\nGQL300: one\nGQL301: two',
      );
    });

    test('keeps its diagnostics unmodifiable', () {
      final error = SchemaBuildError([]);
      expect(
        () => error.diagnostics.add(
          Diagnostic(DiagnosticCode.diagnosticLimitReached, .error, 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
