import 'package:yaml/yaml.dart';

/// A package of the workspace that pub.dev will show, read from its
/// `pubspec.yaml` the way pub reads it.
final class PublishablePackage(
  /// The folder of the package in `packages/`, which is also its name.
  final String name,

  /// The parsed pubspec.
  final YamlMap pubspec,
) {
  /// Creates a package.
  this;

  /// The text of the top-level [key], or null when it is absent or not
  /// text. A folded block (`>-`) is already joined into one line.
  String? field(String key) => switch (pubspec[key]) {
    final String text => text,
    _ => null,
  };

  /// The `topics` entries as written, empty when there are none.
  List<String> get topics => switch (pubspec['topics']) {
    final YamlList list => [for (final topic in list) '$topic'],
    _ => const [],
  };
}
