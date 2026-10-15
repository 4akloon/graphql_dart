import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import '../emit/input_field.dart';

/// The top-level names one generation declares, with what declared each, so
/// that two declarations with one name, or a name that hides a Dart type the
/// generated code uses, are diagnostics instead of broken code.
final class GeneratedNames {
  /// Creates a registry; [mappedCoreTypes] are the `dart:core` types the
  /// configuration maps scalars to, which are as reserved as
  /// [reservedTypeNames].
  GeneratedNames({Iterable<String> mappedCoreTypes = const []})
    : _reserved = {...reservedTypeNames, ...mappedCoreTypes};

  /// The Dart types the generated code uses by their bare names.
  static const Set<String> reservedTypeNames = {
    'bool',
    'double',
    'int',
    'num',
    'String',
    'List',
    'Map',
    'Object',
    'Null',
    'Never',
    'Function',
    'Record',
    'Type',
    'Symbol',
    'Deprecated',
    'override',
    'DateTime',
    'Duration',
    'Uri',
    'BigInt',
  };

  final Set<String> _reserved;
  final Map<String, (String, SourceSpan?)> _declared = {};
  final List<Diagnostic> _diagnostics = [];

  /// The problems found so far, in registration order.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Records that [declarer] (such as `the enum 'Role'`) declares [name].
  void register(String name, String declarer, SourceSpan? span) {
    if (_reserved.contains(name)) {
      _diagnostics.add(
        Diagnostic(
          .reservedTypeName,
          .error,
          "The generated name '$name' would hide the Dart type '$name' the "
          'generated code uses.',
          span: span,
        ),
      );
    }
    final first = _declared[name];
    if (first == null) {
      _declared[name] = (declarer, span);
      return;
    }
    _diagnostics.add(
      Diagnostic(
        .generatedNameCollision,
        .error,
        "The generated name '$name' is declared twice: by ${first.$1} and by "
        '$declarer.',
        span: span,
        related: [?first.$2],
      ),
    );
  }

  /// Records every name the classes of the enum or input object [type]
  /// declare; any other type declares none.
  void registerSchemaType(SchemaType type) {
    const names = DartNames();
    final base = names.typeName(type.name);
    switch (type) {
      case EnumType():
        final declarer = "the enum '${type.name}'";
        for (final name in [base, '${base}Known', '${base}Unknown']) {
          register(name, declarer, type.span);
        }
      case InputObjectType(:final fields, :final isOneOf):
        final declarer = "the input object '${type.name}'";
        register(base, declarer, type.span);
        if (isOneOf) {
          for (final field in fields) {
            final variant = names.capitalized(
              InputField.dartNameOf(field.name),
            );
            register('$base$variant', declarer, type.span);
          }
        }
      case _:
    }
  }
}
