import 'dart:io';

/// The Markdown files the documentation tests read, from the package
/// folder, which is where `dart test` runs: the guides in `doc/`, the
/// package README and the repository README.
final class DocFiles {
  /// Creates the reader.
  const DocFiles();

  /// The guides, `doc/*.md`, keyed by their path from the package folder,
  /// in name order.
  Map<String, String> guides() => _read(
    Directory('doc')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll(r'\', '/'))
        .where((path) => path.endsWith('.md')),
  );

  /// The guides and the two READMEs, keyed by their path from the package
  /// folder.
  Map<String, String> all() => {
    ...guides(),
    ..._read(const ['README.md', '../../README.md']),
  };

  Map<String, String> _read(Iterable<String> paths) => {
    for (final path in paths.toList()..sort())
      path: File(path).readAsStringSync(),
  };
}
