import 'package:typed_graphql/typed_graphql.dart';

/// What a generated schema holds, read from the model, so a fuzzer can
/// check that its generator reaches every element it should.
final class SchemaCoverage {
  /// Creates the reader; it keeps no state.
  const SchemaCoverage();

  /// The names of the features [schema] shows.
  Set<String> of(Schema schema) {
    final features = <String>{
      if (schema.directives.isNotEmpty) 'directive',
      if (schema.directives.any((directive) => directive.isRepeatable))
        'repeatable directive',
      if (schema.directives.any((directive) => !directive.isRepeatable))
        'non-repeatable directive',
      if (schema.typeNamed('Query') != null) 'Query',
      if (schema.queryTypeName != null) 'query root',
      if (schema.mutationTypeName != null) 'mutation root',
      if (schema.subscriptionTypeName != null) 'subscription root',
      if (schema.description != null) 'schema description',
      if (schema.appliedDirectives.isNotEmpty) 'schema directive',
    };
    final descriptions = <String?>[
      schema.description,
      for (final directive in schema.directives) directive.description,
    ];
    final applied = <AppliedDirective>[
      ...schema.appliedDirectives,
      for (final directive in schema.directives) ...directive.appliedDirectives,
    ];
    final inputs = <InputValue>[
      for (final directive in schema.directives) ...directive.arguments,
    ];
    for (final type in schema.types) {
      features.add('${type.runtimeType}');
      descriptions.add(type.description);
      applied.addAll(type.appliedDirectives);
      switch (type) {
        case ScalarType(:final specifiedByUrl):
          if (specifiedByUrl != null) features.add('specifiedBy');
        case ObjectType(:final fields):
          _fields(fields, features, descriptions, applied, inputs);
        case InterfaceType(:final interfaces, :final fields):
          if (interfaces.isNotEmpty) features.add('interface implements');
          _fields(fields, features, descriptions, applied, inputs);
        case UnionType():
          break;
        case EnumType(:final values):
          for (final value in values) {
            descriptions.add(value.description);
            applied.addAll(value.appliedDirectives);
            if (value.deprecationReason != null) features.add('deprecated');
          }
        case InputObjectType(:final fields, :final isOneOf):
          if (isOneOf) features.add('oneOf');
          inputs.addAll(fields);
      }
    }
    for (final input in inputs) {
      descriptions.add(input.description);
      applied.addAll(input.appliedDirectives);
      if (input.deprecationReason != null) features.add('deprecated');
      if (input.defaultValue case final value?) {
        features.add('default ${value.runtimeType}');
      }
    }
    if (applied.any((directive) => directive.arguments.isNotEmpty)) {
      features.add('directive with arguments');
    }
    if (descriptions.any(_isAwkward)) features.add('awkward description');
    return features;
  }

  void _fields(
    List<SchemaField> fields,
    Set<String> features,
    List<String?> descriptions,
    List<AppliedDirective> applied,
    List<InputValue> inputs,
  ) {
    for (final field in fields) {
      descriptions.add(field.description);
      applied.addAll(field.appliedDirectives);
      inputs.addAll(field.arguments);
      if (field.deprecationReason != null) features.add('deprecated');
    }
  }

  bool _isAwkward(String? text) =>
      text != null &&
      (text.contains('"') || text.contains('\n') || text.contains(r'\'));
}
