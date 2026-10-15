import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// The key of a document text in the cache: the lower-case hex SHA-256 of its
/// UTF-8 bytes, which is also the hash of Apollo's persisted queries.
@internal
final class DocumentHash {
  /// Creates the hasher.
  const DocumentHash();

  /// The hash of [text].
  String of(String text) => sha256.convert(utf8.encode(text)).toString();
}
