import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';

/// Checks that each scalar the configuration maps is a custom scalar of the
/// schema (`GQL505`).
final class const ScalarMappingChecker() {
  /// Creates the checker.
  this;

  static const _builtIn = {'Int', 'Float', 'String', 'Boolean', 'ID'};

  /// The problems of [config]'s mappings against [schema], in name order.
  List<Diagnostic> check(CodegenConfig config, Schema schema) {
    final problems = <Diagnostic>[];
    for (final MapEntry(:key, :value) in config.scalars.entries) {
      final message = _problemWith(key, schema);
      if (message != null) {
        problems.add(
          Diagnostic(.unknownScalarMapping, .error, message, span: value.span),
        );
      }
    }
    return problems;
  }

  String? _problemWith(String name, Schema schema) {
    if (_builtIn.contains(name)) {
      return "The built-in scalar '$name' cannot be mapped.";
    }
    return switch (schema.typeNamed(name)) {
      null => "No scalar '$name' in the schema to map.",
      ScalarType() => null,
      _ => "'$name' is not a scalar, so it cannot be mapped.",
    };
  }
}
