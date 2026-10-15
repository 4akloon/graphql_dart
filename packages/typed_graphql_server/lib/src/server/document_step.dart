import 'package:meta/meta.dart';

import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_entry.dart';

/// The core step of the document phase: the text becomes a validated
/// document or its errors, through the cache (R5.2).
@internal
final class DocumentStep {
  /// Creates the step over [cache] and [compiler].
  const DocumentStep(this.cache, this.compiler);

  /// Where compiled texts are kept.
  final DocumentCache cache;

  /// Compiles a text the cache does not hold.
  final DocumentCompiler compiler;

  /// The entry for [text].
  DocumentEntry run(String text) => cache.entryFor(text, compiler);
}
