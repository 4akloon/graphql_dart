import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();
  List<String> names(FieldSelection selection) => [
    for (final field in selection.fields) field.name,
  ];
  List<String> keys(FieldSelection selection) => [
    for (final field in selection.fields) field.responseKey,
  ];

  group('fields', () {
    test('flatten fragments and merge repeated fields', () async {
      final selection = await f.selection('user', '''
        { user { ...Parts name ... on User { friend { name } } } }
        fragment Parts on User { name posts { title } }
      ''');
      expect(names(selection), ['name', 'posts', 'friend']);
    });

    test('leave out a field that @skip removes', () async {
      final selection = await f.selection(
        'user',
        r'query($s: Boolean!) { user { name posts @skip(if: $s) { title } } }',
        variables: JsonObject({'s': const JsonBool(true)}),
      );
      expect(names(selection), ['name']);
    });

    test('keep a field that @include keeps', () async {
      const text =
          r'query($i: Boolean!) { user { name posts @include(if: $i) { title } } }';
      final kept = await f.selection(
        'user',
        text,
        variables: JsonObject({'i': const JsonBool(true)}),
      );
      final dropped = await f.selection(
        'user',
        text,
        variables: JsonObject({'i': const JsonBool(false)}),
      );
      expect(
        [names(kept), names(dropped)],
        [
          ['name', 'posts'],
          ['name'],
        ],
      );
    });

    test('keep each alias as its own field', () async {
      final selection = await f.selection(
        'user',
        '{ user { first: name second: name name } }',
      );
      expect(keys(selection), ['first', 'second', 'name']);
    });

    test('tell the alias from the name', () async {
      final selection = await f.selection(
        'user',
        '{ user { shown: name name } }',
      );
      expect(
        [for (final field in selection.fields) field.alias],
        [
          'shown',
          null,
        ],
      );
    });

    test('hide __typename', () async {
      final selection = await f.selection(
        'user',
        '{ user { __typename name } }',
      );
      expect(names(selection), ['name']);
    });

    test('are empty for a field of a leaf type', () async {
      final selection = await f.selection('plain', '{ plain }');
      expect(selection.fields, isEmpty);
    });

    test('collect what every possible type of an interface selects', () async {
      final selection = await f.selection('pet', '''
        { pet { name ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection), ['name', 'barks', 'meows']);
    });

    test('collect what every member of a union selects', () async {
      final selection = await f.selection('found', '''
        { found { ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection), ['barks', 'meows']);
    });
  });

  group('forType', () {
    const text = '''
      { pet { name ... on Dog { barks } ... on Cat { meows } } }
    ''';

    test('gives the view of one object type', () async {
      final selection = await f.selection('pet', text);
      expect(
        [names(selection.forType('Dog')), names(selection.forType('Cat'))],
        [
          ['name', 'barks'],
          ['name', 'meows'],
        ],
      );
    });

    test('is empty for an unknown type name', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('Nope').fields, isEmpty);
    });

    test('is empty for a type the field cannot have', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('User').fields, isEmpty);
    });

    test('is empty for an interface name, which is no object type', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('Pet').fields, isEmpty);
    });

    test('applies to a union', () async {
      final selection = await f.selection('found', '''
        { found { ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection.forType('Cat')), ['meows']);
    });
  });

  group('has', () {
    const text = '{ user { name posts { title comments { body } } } }';

    test('finds a nested path', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('posts.comments.body'), isTrue);
    });

    test('finds a single name', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('name'), isTrue);
    });

    test('misses a field the request did not select', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('posts.author'), isFalse);
    });

    test('misses a path that goes through a leaf', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('name.first'), isFalse);
    });

    test('reads names, not aliases', () async {
      final selection = await f.selection('user', '{ user { a: name } }');
      expect([selection.has('name'), selection.has('a')], [true, false]);
    });

    test('follows every occurrence of a name', () async {
      final selection = await f.selection('user', '''
        { user { a: posts { title } b: posts { comments { body } } } }
      ''');
      expect(selection.has('posts.comments.body'), isTrue);
    });

    for (final path in ['', 'posts..title', '.posts', 'posts.']) {
      test('throws on the empty segment of "$path"', () async {
        final selection = await f.selection('user', text);
        expect(() => selection.has(path), throwsArgumentError);
      });
    }
  });

  group('fieldsNamed', () {
    test('lists every occurrence, aliases apart', () async {
      final selection = await f.selection(
        'user',
        '{ user { a: name name friend { name } } }',
      );
      expect(
        [for (final field in selection.fieldsNamed('name')) field.responseKey],
        ['a', 'name'],
      );
    });

    test('is empty for a name not selected', () async {
      final selection = await f.selection('user', '{ user { name } }');
      expect(selection.fieldsNamed('posts'), isEmpty);
    });
  });

  group('arguments', () {
    test('are the coerced values with defaults and enums', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: 3, order: desc) { title } } }',
      );
      expect(selection.fields.single.arguments.coerced, {
        'first': 3,
        'order': Sorting.desc,
      });
    });

    test('substitute the variables of the request', () async {
      final selection = await f.selection(
        'user',
        r'query($n: Int) { user { posts(first: $n) { title } } }',
        variables: JsonObject({'n': JsonNumber(5)}),
      );
      expect(selection.fields.single.arguments.coerced['first'], 5);
    });

    test('read as absent when the value fails coercion', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: "many") { title } } }',
      );
      expect(selection.fields.single.arguments.coerced, isEmpty);
    });

    test('belong to the field, with its own sub-selection', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: 1) { title comments { body } } } }',
      );
      expect(names(selection.fields.single.selection), ['title', 'comments']);
    });
  });

  group('FieldInfo.selection', () {
    test('is the same object each time it is read', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      expect(identical(info.selection, info.selection), isTrue);
    });

    test('is not built until it is read', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      var reads = 0;
      final copy = FieldInfo(
        fieldName: info.fieldName,
        parentType: info.parentType,
        returnType: info.returnType,
        path: info.path,
        fieldNodes: info.fieldNodes,
        operation: info.operation,
        variables: info.variables,
        schema: info.schema,
        selectionReader: () {
          reads++;
          return FieldSelection.empty;
        },
      );
      final before = reads;
      final same = identical(copy.selection, copy.selection);
      expect([before, reads, same], [0, 1, true]);
    });

    test('is empty when the call was not made by an execution', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      final copy = FieldInfo(
        fieldName: info.fieldName,
        parentType: info.parentType,
        returnType: info.returnType,
        path: info.path,
        fieldNodes: info.fieldNodes,
        operation: info.operation,
        variables: info.variables,
        schema: info.schema,
      );
      expect(copy.selection.fields, isEmpty);
    });
  });
}
