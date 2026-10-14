/// One link of an `llms.txt` section, written `- [title](url): description`.
final class LlmsEntry(
  /// The link text.
  final String title,

  /// The link target.
  final String url,

  /// The text after the colon; empty when the line has none.
  final String description,
) {
  /// Creates an entry.
  this;
}
