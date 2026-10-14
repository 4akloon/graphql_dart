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
  List<PublishablePackage> publishable() {
    final names = [
      for (final folder in Directory('packages').listSync())
        if (folder is Directory)
          folder.path.replaceAll(r'\', '/').split('/').last,
    ]..sort();
    return [
      for (final name in names)
        if (_pubspecOf(name) case final pubspec?
            when pubspec['publish_to'] != 'none')
          PublishablePackage(name, pubspec),
    ];
  }

  YamlMap? _pubspecOf(String name) {
    final file = File('packages/$name/pubspec.yaml');
    if (!file.existsSync()) return null;
    return switch (loadYaml(file.readAsStringSync())) {
      final YamlMap pubspec => pubspec,
      _ => throw FormatException('packages/$name/pubspec.yaml is not a map'),
    };
  }
}
