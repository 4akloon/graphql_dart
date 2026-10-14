import 'dart:math';

/// Breaks an introspection result, given as plain Dart maps and lists,
/// the ways a hostile or broken server can: a member removed, a value of
/// another JSON type, an unknown kind, name or location, a list item
/// repeated or dropped.
final class IntrospectionMutator {
  /// Draws from [random].
  IntrospectionMutator(this.random);

  /// The random source.
  final Random random;

  /// Values put where any value was; each is wrong somewhere.
  static const List<Object?> _hostileValues = [
    null,
    0,
    -1.5,
    true,
    '',
    'x',
    '{',
    '[1,',
    r'$v',
    'NON_NULL',
    'LIST',
    'OBJECT',
    'SCALAR',
    'UNKNOWN',
    'QUERY',
    'NOT_A_LOCATION',
    'Missing',
    'String',
    '__Type',
    <Object?>[],
    <String, Object?>{},
    <Object?>[null, 1],
    {'kind': 'LIST'},
    {'kind': 'NON_NULL', 'name': null, 'ofType': null},
    {'kind': 'OBJECT', 'name': 'Missing', 'ofType': null},
  ];

  /// [json] with one to five breaks, in place; one result in fifty loses
  /// or breaks `__schema` itself, which a pick among every map and list
  /// would almost never do.
  void mutate(Map<String, Object?> json) {
    if (random.nextInt(50) == 0) {
      _breakOne(json);
    }
    for (var step = random.nextInt(5); step >= 0; step--) {
      final containers = _containers(json);
      _breakOne(containers[random.nextInt(containers.length)]);
    }
  }

  void _breakOne(Object container) {
    switch (container) {
      case final Map<String, Object?> map when map.isNotEmpty:
        final key = map.keys.elementAt(random.nextInt(map.length));
        if (random.nextInt(3) == 0) {
          map.remove(key);
        } else {
          map[key] = _hostile();
        }
      case final List<Object?> list when list.isNotEmpty:
        final index = random.nextInt(list.length);
        switch (random.nextInt(3)) {
          case 0:
            list.removeAt(index);
          case 1:
            list.add(list[index]);
          default:
            list[index] = _hostile();
        }
      default:
    }
  }

  /// A hostile value; a map or a list is a fresh copy, so a later break
  /// cannot change the constant.
  Object? _hostile() =>
      switch (_hostileValues[random.nextInt(_hostileValues.length)]) {
        final Map<String, Object?> map => <String, Object?>{...map},
        final List<Object?> list => <Object?>[...list],
        final value => value,
      };

  /// Every map and list in [json], found with an explicit stack.
  List<Object> _containers(Map<String, Object?> json) {
    final found = <Object>[];
    final stack = <Object?>[json];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case final Map<String, Object?> map:
          found.add(map);
          stack.addAll(map.values);
        case final List<Object?> list:
          found.add(list);
          stack.addAll(list);
        default:
      }
    }
    return found;
  }
}
