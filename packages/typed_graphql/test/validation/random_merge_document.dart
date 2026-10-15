import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// Random operations with a few fragments over a small schema, text that
/// stresses field merging: aliases, arguments, interfaces, unions, spreads
/// beside and inside fields.
final class RandomMergeDocument(final Random random, final Schema schema) {
  /// Creates a generator drawing from [random], over [schema] (see [sdl]).
  this;

  /// The schema the documents are written against.
  static const String sdl = '''
type Query { a: T b: T i: I u: U s: String }
input In { p: Int q: Int }
interface I { x: String y: Int t: I l: [String] k(a: Int): Int }
type T implements I { x: String y: Int t: T l: [String] k(a: Int): Int m(a: Int b: In c: [Int]): Int }
type V implements I { x: Int y: String t: V l: [String!] k(a: Int): Int }
type W implements I { x: String y: Int t: W l: [String] k(a: Int): Int }
union U = T | V
''';

  int _fragmentCount = 0;

  /// The text of one random document.
  String next() {
    _fragmentCount = 1 + random.nextInt(3);
    final buffer = StringBuffer('query(\$v: Int){ ${_set('Query', 2, -1)} }');
    for (var i = 0; i < _fragmentCount; i++) {
      final type = _pick(['T', 'V', 'W', 'I']);
      buffer.write(' fragment F$i on $type { ${_set(type, 2, i)} }');
    }
    return buffer.toString();
  }

  T _pick<T>(List<T> list) => list[random.nextInt(list.length)];

  String _set(String type, int depth, int fragment) {
    final parts = [
      for (var i = 0, n = 1 + random.nextInt(3); i < n; i++)
        _selection(type, depth, fragment),
    ];
    return parts.join(' ');
  }

  String _selection(String type, int depth, int fragment) {
    final kind = random.nextInt(10);
    if (kind == 0 && fragment + 1 < _fragmentCount) {
      final later =
          fragment + 1 + random.nextInt(_fragmentCount - fragment - 1);
      return '...F$later';
    }
    if (kind == 1) {
      final condition = random.nextBool() ? null : _pick(['T', 'V', 'W', 'I']);
      final inner = condition ?? type;
      final on = condition == null ? '' : 'on $condition ';
      return '... $on{ ${_set(inner, depth, fragment)} }';
    }
    return _field(type, depth, fragment);
  }

  String _field(String type, int depth, int fragment) {
    final fields = switch (schema.typeNamed(type)) {
      ObjectType(:final fields) => fields,
      InterfaceType(:final fields) => fields,
      _ => const <SchemaField>[],
    };
    if (fields.isEmpty) return '__typename';
    final field = _pick(fields);
    final alias = _pick(['', '', 'p: ', 'q: ']);
    final arguments = switch (field.name) {
      'k' => _pick(['', '(a: 1)', '(a: 2)', '(a: \$v)']),
      'm' => _pick([
        '',
        '(a: 1 b: {p: 1 q: 2})',
        '(b: {q: 2 p: 1} a: 1)',
        '(c: [1,2])',
        '(c: [2,1])',
        '(c: [1,2] a: 1)',
      ]),
      _ => '',
    };
    final named = _named(field.type);
    if (named == null || named.isLeafType)
      return '$alias${field.name}$arguments';
    if (depth <= 0) return '$alias${field.name}$arguments { __typename }';
    return '$alias${field.name}$arguments '
        '{ ${_set(named.name, depth - 1, fragment)} }';
  }

  SchemaType? _named(TypeRef type) => switch (type) {
    ListType(:final type) => _named(type),
    NonNullType(:final type) => _named(type),
    NamedType(:final name) => schema.typeNamed(name.value),
  };
}
