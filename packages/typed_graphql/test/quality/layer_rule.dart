/// The core's import rules (spec §1, R0.6), checked on the text of one
/// library under `lib/src/`.
///
/// Every library lives in a layer folder. A layer imports only its own
/// folder and the layers listed before it; the core imports no platform
/// library outside pure Dart and no package other than `meta`.
final class LayerRule {
  /// Creates the rule.
  const LayerRule();

  /// The layer folders under `lib/src/`, lowest first. A folder that does
  /// not exist yet is simply not scanned.
  static const List<String> layers = [
    'diagnostics',
    'language',
    'protocol',
    'schema',
    'validation',
  ];

  /// The platform libraries that run on the VM, AOT, dart2js and dart2wasm.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:math',
    'dart:typed_data',
  };

  static final RegExp _directive = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// The violations in [content], the text of the library at [filePath].
  ///
  /// [filePath] contains `lib/src/` and may use `\` (Windows) or `/`.
  List<String> check(String filePath, String content) {
    final path = _pathInSrc(filePath);
    final layer = _layerOf(path);
    if (layer == null) {
      return ['$path is not in a layer folder: ${layers.join(', ')}'];
    }
    return [
      for (final match in _directive.allMatches(content))
        ?_violation(path, layer, match.group(1)!),
    ];
  }

  /// What is wrong with [path], in [layer], importing [target]; null when
  /// nothing is.
  String? _violation(String path, int layer, String target) {
    if (target.startsWith('dart:')) {
      return _pureDart.contains(target)
          ? null
          : '$path imports $target: the core is pure Dart (R0.6)';
    }
    if (target.startsWith('package:')) {
      return target.startsWith('package:meta/')
          ? null
          : '$path imports $target: the core depends only on meta';
    }
    final resolved = Uri.parse(path).resolve(target).path;
    final targetLayer = _layerOf(resolved);
    if (targetLayer == null) {
      return '$path imports $target, which is not in a layer folder';
    }
    return targetLayer > layer
        ? '$path imports $target: ${layers[layer]} must not depend on '
              '${layers[targetLayer]}'
        : null;
  }

  /// [filePath] from the folder after `lib/src/`, with `/` separators.
  String _pathInSrc(String filePath) {
    final path = filePath.replaceAll(r'\', '/');
    const marker = 'lib/src/';
    final start = path.indexOf(marker);
    if (start < 0) {
      throw ArgumentError.value(filePath, 'filePath', 'is not in lib/src');
    }
    return path.substring(start + marker.length);
  }

  /// The index in [layers] of the folder [path] starts with; null when it
  /// starts with no layer folder.
  int? _layerOf(String path) {
    final slash = path.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final index = layers.indexOf(path.substring(0, slash));
    return index < 0 ? null : index;
  }
}
