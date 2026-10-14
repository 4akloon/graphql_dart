import 'dart:io';

/// The Dart files the code rules check: `lib/`, `bin/`, `test/` and
/// `tool/` of every package in `packages/`, and the workspace's own
/// `test/`.
final class WorkspaceFiles(
  /// The workspace root, the folder of the root `pubspec.yaml`.
  final String root,
) {
  /// Creates a reader of the workspace at [root].
  this;

  /// The content of every file, keyed by its path from [root] with `/`
  /// separators, in path order.
  Map<String, String> read() {
    final folders = [
      for (final package in _packages())
        for (final folder in const ['lib', 'bin', 'test', 'tool'])
          Directory('${package.path}/$folder'),
      Directory('$root/test'),
    ];
    final files = {
      for (final folder in folders)
        if (folder.existsSync())
          for (final file in folder.listSync(recursive: true).whereType<File>())
            if (file.path.endsWith('.dart'))
              _relative(file.path): file.readAsStringSync(),
    };
    return Map.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<Directory> _packages() =>
      Directory('$root/packages').listSync().whereType<Directory>().toList();

  String _relative(String path) =>
      path.substring(root.length + 1).replaceAll(r'\', '/');
}
