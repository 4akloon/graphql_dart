import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'dart_reference.dart';

/// Reads a [DartReference] written as `<library>#<Name>` or, for a `dart:core`
/// type, as its bare name.
final class const DartReferenceReader() {
  /// Creates the reader.
  this;

  static final RegExp _library = RegExp(
    r'^(package:[^#\s]+\.dart|dart:[a-z_]+)$',
  );
  static final RegExp _identifier = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');
  static const Set<String> _coreTypes = {
    'BigInt',
    'bool',
    'DateTime',
    'double',
    'Duration',
    'int',
    'num',
    'Object',
    'String',
    'Uri',
  };

  /// Returns the reference [node] holds under [label], or reports the problem
  /// and returns null. A reference without a library is accepted only when
  /// [isBareCoreAllowed] and it names a `dart:core` type.
  DartReference? read(
    YamlNode node,
    String label,
    ConfigReport report, {
    required bool isBareCoreAllowed,
  }) {
    final text = report.string(node, label);
    if (text == null) return null;
    final hash = text.indexOf('#');
    if (hash < 0) {
      return _readBare(node, label, text, report, isBareCoreAllowed);
    }
    final library = text.substring(0, hash);
    final name = text.substring(hash + 1);
    final isCoreName = library != 'dart:core' || _coreTypes.contains(name);
    if (!_library.hasMatch(library) ||
        !_identifier.hasMatch(name) ||
        !isCoreName) {
      report.error(
        node,
        "'$label' must be '<library>#<Name>', such as "
        "'package:my_app/codecs.dart#MyType'.",
      );
      return null;
    }
    return DartReference(library == 'dart:core' ? null : library, name);
  }

  DartReference? _readBare(
    YamlNode node,
    String label,
    String text,
    ConfigReport report,
    bool isBareCoreAllowed,
  ) {
    if (isBareCoreAllowed && _coreTypes.contains(text)) {
      return DartReference(null, text);
    }
    report.error(
      node,
      "'$label' names '$text' without a library; write "
      "'package:...#$text'.",
    );
    return null;
  }
}
