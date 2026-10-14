import 'package:meta/meta.dart';

/// A position in a GraphQL document as people count it: a 1-based [line]
/// and a 1-based [column] in UTF-16 code units.
///
/// It is also the shape of an entry of a GraphQL error's `locations`
/// (spec §7.1.2, "Error Result Format").
@immutable
final class const SourceLocation(
  /// The line, from 1.
  final int line,

  /// The column, from 1, counted in UTF-16 code units.
  final int column,
) {
  /// Creates a location; [line] and [column] are 1 or more.
  this
    : assert(line >= 1, 'line is 1-based'),
      assert(column >= 1, 'column is 1-based');

  @override
  bool operator ==(Object other) =>
      other is SourceLocation && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}
