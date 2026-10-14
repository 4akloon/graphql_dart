import 'dart:io';

import 'package:yaml/yaml.dart';

import 'publishable_package.dart';

/// Reads the packages in `packages/` from the workspace root, where the
/// workspace suite runs.
final class WorkspacePackages {
  /// Creates the reader.
  const WorkspacePackages();

  /// Every package whose pubspec does not say `publish_to: none`, in name
  /// order.
  List<PublishablePackage> publishable() => [
    for (final name in names)
      if (_pubspecOf(name) case final pubspec?
          when pubspec['publish_to'] != 'none')
        PublishablePackage(name, pubspec),
  ];

  /// The folder names in `packages/`, sorted: the one listing every other
  /// reader here uses.
  List<String> get names => [
    for (final folder in Directory('packages').listSync())
      if (folder is Directory)
        folder.path.replaceAll(r'\', '/').split('/').last,
  ]..sort();

  /// The paths of the READMEs that exist, one per package folder.
  List<String> readmePaths() => [
    for (final name in names)
      if (File('packages/$name/README.md').existsSync())
        'packages/$name/README.md',
  ];

  YamlMap? _pubspecOf(String name) {
    final file = File('packages/$name/pubspec.yaml');
    if (!file.existsSync()) return null;
    return switch (loadYaml(file.readAsStringSync())) {
      final YamlMap pubspec => pubspec,
      _ => throw FormatException('packages/$name/pubspec.yaml is not a map'),
    };
  }
}
