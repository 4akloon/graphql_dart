import 'package:meta/meta.dart';

/// The introspection query (spec §4): the operation a client sends to read
/// a schema, as graphql-js's `getIntrospectionQuery` writes it.
///
/// Each flag adds fields that a server of an older edition, or one without
/// a working-draft feature, may lack; [text] is the query. [full] is what
/// a September2025 server answers and what `Schema.toIntrospection` writes
/// by default.
///
/// {@category introspection}
@immutable
final class const IntrospectionQuery({
  /// Whether types, fields, arguments, enum values and directives read
  /// their `description`.
  final bool includesDescriptions = true,

  /// Whether scalars read `specifiedByURL`.
  final bool includesSpecifiedByUrl = false,

  /// Whether directives read `isRepeatable`.
  final bool includesDirectiveIsRepeatable = false,

  /// Whether the schema reads its `description`; only with
  /// [includesDescriptions].
  final bool includesSchemaDescription = false,

  /// Whether arguments and input fields are read with their deprecated
  /// ones, `isDeprecated` and `deprecationReason`.
  final bool includesInputValueDeprecation = false,

  /// Whether directives are read with their deprecated ones,
  /// `isDeprecated` and `deprecationReason`: a working-draft feature that
  /// September2025 introspection lacks.
  final bool includesDirectiveDeprecation = false,

  /// Whether input objects read `isOneOf`.
  final bool includesOneOf = false,

  /// How many `ofType` levels a type reference reads, from 0 to 100; a
  /// deeper type reads as cut off.
  final int typeDepth = 9,
}) {
  /// Creates the query with graphql-js's default options.
  this;

  /// Every field September2025 introspection has: graphql-js's
  /// `introspectionFromSchema` options without directive deprecation,
  /// which the edition lacks (R0.1).
  static const IntrospectionQuery full = IntrospectionQuery(
    includesSpecifiedByUrl: true,
    includesDirectiveIsRepeatable: true,
    includesSchemaDescription: true,
    includesInputValueDeprecation: true,
    includesOneOf: true,
  );

  static const String _depthMessage =
      'Please set typeDepth to a reasonable value between 0 and 100; the '
      'default is 9.';

  /// The query text: the operation `IntrospectionQuery` and the fragments
  /// `FullType`, `InputValue` and `TypeRef`.
  ///
  /// A [typeDepth] outside 0 to 100 is a [RangeError] with graphql-js's
  /// message.
  String get text {
    RangeError.checkValueInInterval(
      typeDepth,
      0,
      100,
      'typeDepth',
      _depthMessage,
    );
    return [
      ..._operation,
      '',
      ..._fullType,
      '',
      ..._inputValue,
      '',
      ..._typeRef,
    ].join('\n');
  }

  String get _directiveArguments =>
      includesDirectiveDeprecation ? '(includeDeprecated: true)' : '';

  String get _inputArguments =>
      includesInputValueDeprecation ? '(includeDeprecated: true)' : '';

  List<String> get _operation => [
    'query IntrospectionQuery {',
    '  __schema {',
    if (includesSchemaDescription && includesDescriptions) '    description',
    '    queryType { name kind }',
    '    mutationType { name kind }',
    '    subscriptionType { name kind }',
    '    types {',
    '      ...FullType',
    '    }',
    '    directives$_directiveArguments {',
    '      name',
    if (includesDescriptions) '      description',
    if (includesDirectiveIsRepeatable) '      isRepeatable',
    if (includesDirectiveDeprecation) ...[
      '      isDeprecated',
      '      deprecationReason',
    ],
    '      locations',
    '      args$_inputArguments {',
    '        ...InputValue',
    '      }',
    '    }',
    '  }',
    '}',
  ];

  List<String> get _fullType => [
    'fragment FullType on __Type {',
    '  kind',
    '  name',
    if (includesDescriptions) '  description',
    if (includesSpecifiedByUrl) '  specifiedByURL',
    if (includesOneOf) '  isOneOf',
    '  fields(includeDeprecated: true) {',
    '    name',
    if (includesDescriptions) '    description',
    '    args$_inputArguments {',
    '      ...InputValue',
    '    }',
    '    type {',
    '      ...TypeRef',
    '    }',
    '    isDeprecated',
    '    deprecationReason',
    '  }',
    '  inputFields$_inputArguments {',
    '    ...InputValue',
    '  }',
    '  interfaces {',
    '    ...TypeRef',
    '  }',
    ..._enumValues,
    '  possibleTypes {',
    '    ...TypeRef',
    '  }',
    '}',
  ];

  List<String> get _enumValues => [
    '  enumValues(includeDeprecated: true) {',
    '    name',
    if (includesDescriptions) '    description',
    '    isDeprecated',
    '    deprecationReason',
    '  }',
  ];

  List<String> get _inputValue => [
    'fragment InputValue on __InputValue {',
    '  name',
    if (includesDescriptions) '  description',
    '  type { ...TypeRef }',
    '  defaultValue',
    if (includesInputValueDeprecation) ...[
      '  isDeprecated',
      '  deprecationReason',
    ],
    '}',
  ];

  // The `ofType` levels nest; they are written with a loop, not recursion.
  List<String> get _typeRef {
    final opening = <String>[];
    final closing = <String>[];
    for (var level = 1; level <= typeDepth; level++) {
      final indent = '  ' * level;
      opening.addAll(['${indent}ofType {', '$indent  name', '$indent  kind']);
      closing.insert(0, '$indent}');
    }
    return [
      'fragment TypeRef on __Type {',
      '  kind',
      '  name',
      ...opening,
      ...closing,
      '}',
    ];
  }
}
