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
  final Map<String, (String, SourceSpan?)> _files = {};
  final List<Diagnostic> _diagnostics = [];

  /// The problems found so far, each once: by file, then offset; the ones
  /// without a place last, in registration order.
  List<Diagnostic> get diagnostics {
    final unique = <Diagnostic>[];
    for (final diagnostic in _diagnostics) {
      if (!unique.contains(diagnostic)) unique.add(diagnostic);
    }
    final indexed = unique.indexed.toList()
      ..sort((a, b) {
        final first = a.$2.span;
        final second = b.$2.span;
        if (first == null || second == null) {
          if (first == second) return a.$1.compareTo(b.$1);
          return first == null ? 1 : -1;
        }
        final byFile = first.source.name.compareTo(second.source.name);
        if (byFile != 0) return byFile;
        final byOffset = first.start.compareTo(second.start);
        return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
      });
    return List.unmodifiable([
      for (final (_, diagnostic) in indexed) diagnostic,
    ]);
  }

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

  /// Records that [declarer] writes the file at [path]; a second writer is a
  /// problem.
  void registerFile(String path, String declarer, SourceSpan? span) {
    final first = _files[path];
    if (first == null) {
      _files[path] = (declarer, span);
      return;
    }
    _diagnostics.add(
      Diagnostic(
        .generatedNameCollision,
        .error,
        "The generated file '$path' is written twice: by ${first.$1} and by "
        '$declarer.',
        span: span,
        related: [?first.$2],
      ),
    );
  }

  /// Records every name the classes of the enum or input object [type]
  /// declare; any other type declares none.
  void registerSchemaType(SchemaType type) {
    switch (type) {
      case EnumType():
        _registerEnum(type);
      case InputObjectType():
        _registerInputObject(type);
      case _:
    }
  }

  void _registerEnum(EnumType type) {
    const names = DartNames();
    final base = names.typeName(type.name);
    final declarer = "the enum '${type.name}'";
    for (final name in [base, '${base}Known', '${base}Unknown']) {
      register(name, declarer, type.span);
    }
    registerMembers(declarer, [
      for (final value in type.values)
        (
          names.memberName(value.name, reservedMembers: DartNames.enumMembers),
          "the value '${value.name}'",
          value.span ?? type.span,
        ),
    ]);
  }

  void _registerInputObject(InputObjectType type) {
    const names = DartNames();
    final base = names.typeName(type.name);
    final declarer = "the input object '${type.name}'";
    register(base, declarer, type.span);
    if (type.isOneOf) {
      for (final field in type.fields) {
        final variant = names.capitalized(InputField.dartNameOf(field.name));
        register('$base$variant', declarer, type.span);
      }
      return;
    }
    registerMembers(declarer, [
      for (final field in type.fields)
        (
          InputField.dartNameOf(field.name),
          "the field '${field.name}'",
          field.span ?? type.span,
        ),
    ]);
  }

  /// Records the [members] (Dart name, declarer, span) of the class that
  /// [owner] describes; two with one Dart name are a problem.
  ///
  /// Several GraphQL names can give one Dart member name (`RED` and `red`,
  /// `first_name` and `firstName`), which would not compile.
  void registerMembers(
    String owner,
    List<(String, String, SourceSpan?)> members,
  ) {
    final Map<String, (String, SourceSpan?)> seen = {};
    for (final (name, declarer, span) in members) {
      final first = seen[name];
      if (first == null) {
        seen[name] = (declarer, span);
        continue;
      }
      _diagnostics.add(
        Diagnostic(
          .generatedNameCollision,
          .error,
          "The generated member '$name' of $owner is declared twice: "
          'by ${first.$1} and by $declarer.',
          span: span,
          related: [?first.$2],
        ),
      );
    }
  }
}
