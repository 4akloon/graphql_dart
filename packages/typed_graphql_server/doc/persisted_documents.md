# Persisted Documents

This guide describes the stores of automatic persisted queries; the server
steps that use them come with the rest of the stage.

`MemoryPersistedQueryStore` keeps the most recently used texts by their
hash, evicting the least recently used one past its capacity.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final store = MemoryPersistedQueryStore(capacity: 1)
    ..write('a', '{ a }')
    ..write('b', '{ b }');
  print(store.read('a'));
  print(store.read('b'));
}
```

It prints:

```text
null
{ b }
```
