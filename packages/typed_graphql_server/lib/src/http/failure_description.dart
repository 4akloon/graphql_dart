import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Words a [DecodeFailure] for a message: its text and, when it has one, the
/// path of the value it is about.
@internal
final class FailureDescription {
  /// Creates the describer.
  const FailureDescription();

  /// The message of [failure], followed by ` at <path>` with the path's
  /// segments joined by `.`, indexes as numbers.
  String of(DecodeFailure failure) {
    if (failure.path.isEmpty) return failure.message;
    final path = failure.path
        .map(
          (segment) => switch (segment) {
            PathKey(:final name) => name,
            PathIndex(:final index) => '$index',
          },
        )
        .join('.');
    return '${failure.message} at $path';
  }
}
