import 'package:meta/meta.dart';

import 'source.dart';
import 'source_location.dart';

/// A range of a [Source]: from [start] up to, not including, [end], both
/// offsets in UTF-16 code units. A diagnostic points at one.
@immutable
final class const SourceSpan(
  /// The source the offsets index.
  final Source source,

  /// The offset of the first code unit of the range.
  final int start,

  /// The offset after the last code unit; equal to [start] for an empty
  /// range, such as the end of the document.
  final int end,
) {
  /// Creates a span; `0 <= start <= end <= source.body.length`, and
  /// [location] and [text] throw a [RangeError] past the end.
  this
    : assert(start >= 0, 'start is not negative'),
      assert(start <= end, 'start is not after end');

  /// The line and column of [start].
  SourceLocation get location => source.locationOf(start);

  /// The text the span covers.
  String get text => source.body.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is SourceSpan &&
      identical(other.source, source) &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(identityHashCode(source), start, end);

  /// `name:line:column` of [start], the form editors and terminals link.
  @override
  String toString() => '${source.name}:$location';
}
