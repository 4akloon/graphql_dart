import 'package:meta/meta.dart';

/// The message that replaces an unexpected error when errors are masked
/// (`GQL330`), shared by the executor, the coercion and the server pipeline.
@internal
final class MaskedMessage {
  /// Creates the holder.
  const MaskedMessage();

  /// The text clients see instead of the error's `toString()`.
  String get text => 'Unexpected error.';
}
