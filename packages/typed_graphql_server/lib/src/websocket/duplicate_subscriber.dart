import 'dart:convert';

import 'package:meta/meta.dart';

/// Builds the reason of the `4409` close: a client reused the id of a
/// running operation.
@internal
final class DuplicateSubscriber {
  /// Creates the builder.
  const DuplicateSubscriber();

  /// The WebSocket close code.
  static const int code = 4409;

  /// The most UTF-8 bytes a close reason may hold (RFC 6455 section 5.5).
  static const int maxReasonBytes = 123;

  /// `Subscriber for <id> already exists`, with [id] cut at a code point
  /// boundary so that the whole reason fits in [maxReasonBytes] bytes; the
  /// id is cut, not the sentence, so the reason still says what happened.
  String reason(String id) {
    const prefix = 'Subscriber for ';
    const suffix = ' already exists';
    const budget = maxReasonBytes - prefix.length - suffix.length;
    final cut = StringBuffer();
    var bytes = 0;
    for (final rune in id.runes) {
      final character = String.fromCharCode(rune);
      bytes += utf8.encode(character).length;
      if (bytes > budget) {
        break;
      }
      cut.write(character);
    }
    return '$prefix$cut$suffix';
  }
}
