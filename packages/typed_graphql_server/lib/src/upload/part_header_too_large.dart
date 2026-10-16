import 'package:meta/meta.dart';

/// The error of a request body whose part header passed the allowed size.
@internal
final class PartHeaderTooLarge implements Exception {
  /// Creates the error for a header limit of [limit] bytes.
  const PartHeaderTooLarge(this.limit);

  /// The most bytes the headers of one part may take.
  final int limit;

  @override
  String toString() => 'PartHeaderTooLarge: more than $limit bytes';
}
