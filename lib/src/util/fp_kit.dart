class FpKit {
  static Map<String, T> getByName<T>(List<T> namedObjects,
      String Function(T) nameFn, T Function(T, T) mergeFunc) {
    final Map<String, T> result = {};
    for (final T namedObject in namedObjects) {
      final String name = nameFn(namedObject);
      if (result.containsKey(name)) {
        result[name] = mergeFunc(result[name] as T, namedObject);
      } else {
        result[name] = namedObject;
      }
    }
    return result;
  }
}
