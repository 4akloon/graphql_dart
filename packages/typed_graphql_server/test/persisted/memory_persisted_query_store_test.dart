import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  test('reads what it wrote', () {
    final store = MemoryPersistedQueryStore()..write('a', '{ a }');
    expect(store.read('a'), '{ a }');
  });

  test('reads null for a hash it does not hold', () {
    expect(MemoryPersistedQueryStore().read('a'), isNull);
  });

  test('evicts the least recently written past the capacity', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }')
      ..write('c', '{ c }');
    expect(store.read('a'), isNull);
  });

  test('keeps the capacity', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }')
      ..write('c', '{ c }');
    expect(store.length, 2);
  });

  test('a read makes a text the most recently used', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }');
    store
      ..read('a')
      ..write('c', '{ c }');
    expect(store.read('a'), '{ a }');
  });

  test('a write of a held hash replaces its text without growing', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('a', '{ b }');
    expect((store.read('a'), store.length), ('{ b }', 1));
  });

  test('a capacity below 1 is an ArgumentError', () {
    expect(() => MemoryPersistedQueryStore(capacity: 0), throwsArgumentError);
  });
}
