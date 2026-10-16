import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'http_options.dart';

/// Checks the [HttpOptions] a handler is built with: a value that makes no
/// sense is a programmer error, not input.
@internal
final class HttpOptionsCheck {
  /// Creates the check.
  const HttpOptionsCheck();

  /// Throws an `ArgumentError` naming the first option of [options] that is
  /// out of range.
  void check(HttpOptions options) {
    _positive(options.maxBodyBytes > 0, options.maxBodyBytes, 'maxBodyBytes');
    _positive(
      options.bodyTimeout > Duration.zero,
      options.bodyTimeout,
      'bodyTimeout',
    );
    _positive(options.maxUriLength > 0, options.maxUriLength, 'maxUriLength');
    if (options.maxJsonDepth < 1 ||
        options.maxJsonDepth > JsonReader.maxSupportedDepth) {
      throw ArgumentError.value(
        options.maxJsonDepth,
        'maxJsonDepth',
        'must be between 1 and ${JsonReader.maxSupportedDepth}',
      );
    }
  }

  void _positive(bool isPositive, Object value, String name) {
    if (!isPositive) {
      throw ArgumentError.value(value, name, 'must be positive');
    }
  }
}
