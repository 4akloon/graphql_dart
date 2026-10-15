/// Sorts a short list as the JavaScript engines' `Array.prototype.sort`
/// does, so a comparator that is not a total order (graphql-js's type
/// suggestions compare by usage, then by inheritance, then by name) gives
/// the order graphql-js gives.
///
/// V8 sorts a list of fewer than 64 items by finding the leading run
/// (reversing it when strictly descending) and inserting the rest by
/// binary search. A longer list falls back to [List.sort], which agrees
/// whenever the comparator is a total order.
final class EngineOrderedSort<T>(final int Function(T a, T b) compare) {
  /// Creates a sort with [compare].
  this;

  static const int _shortListLength = 64;

  /// A new list of [items] in order.
  List<T> sorted(Iterable<T> items) {
    final list = items.toList();
    if (list.length >= _shortListLength) {
      return list..sort(compare);
    }
    if (list.length < 2) {
      return list;
    }
    _insertAfterRun(list, _makeRun(list));
    return list;
  }

  // The length of the leading run, which is reversed when descending.
  int _makeRun(List<T> list) {
    final isDescending = compare(list[1], list[0]) < 0;
    var length = 2;
    while (length < list.length) {
      final order = compare(list[length], list[length - 1]);
      if (isDescending ? order >= 0 : order < 0) {
        break;
      }
      length++;
    }
    if (isDescending) {
      final reversed = list.sublist(0, length).reversed.toList();
      list.setRange(0, length, reversed);
    }
    return length;
  }

  void _insertAfterRun(List<T> list, int runLength) {
    for (var start = runLength; start < list.length; start++) {
      final pivot = list[start];
      var left = 0;
      var right = start;
      while (left < right) {
        final middle = left + ((right - left) >> 1);
        if (compare(pivot, list[middle]) < 0) {
          right = middle;
        } else {
          left = middle + 1;
        }
      }
      list.setRange(left + 1, start + 1, list, left);
      list[left] = pivot;
    }
  }
}
