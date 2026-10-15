/// The size limits of a server; a null limit is off (R5.4, R5.15).
///
/// {@category server}
final class ServerLimits {
  /// Creates limits; every limit but [defaultListSize] is off when null.
  ///
  /// A non-null limit must be positive, [maxCost] not NaN and
  /// [defaultListSize] not negative. These are programmer errors, checked by
  /// assertions because a constant constructor cannot throw an
  /// [ArgumentError].
  const ServerLimits({
    this.maxDocumentLength = 100000,
    this.maxTokens = 15000,
    this.maxDepth,
    this.maxAliases,
    this.maxDirectives,
    this.maxCost,
    this.defaultListSize = 10,
  }) : assert(
         maxDocumentLength == null || maxDocumentLength > 0,
         'maxDocumentLength must be positive',
       ),
       assert(maxTokens == null || maxTokens > 0, 'maxTokens must be positive'),
       assert(maxDepth == null || maxDepth > 0, 'maxDepth must be positive'),
       assert(
         maxAliases == null || maxAliases > 0,
         'maxAliases must be positive',
       ),
       assert(
         maxDirectives == null || maxDirectives > 0,
         'maxDirectives must be positive',
       ),
       assert(
         maxCost == null || maxCost > 0,
         'maxCost must be positive (NaN fails the comparison)',
       ),
       assert(defaultListSize >= 0, 'defaultListSize must not be negative');

  /// The limits of a server in development: the bounds on the text only.
  static const ServerLimits development = ServerLimits();

  /// The limits of a server in production: also depth, aliases, directives
  /// and cost.
  static const ServerLimits production = ServerLimits(
    maxDepth: 15,
    maxAliases: 15,
    maxDirectives: 50,
    maxCost: 10000,
  );

  /// The longest document text accepted, in UTF-16 code units; checked
  /// before hashing and parsing, and refused with `GQL401`.
  final int? maxDocumentLength;

  /// The most tokens the parser reads (`ParserOptions.maxTokens`).
  final int? maxTokens;

  /// The deepest selection nesting, applied by `MaxDepthRule` (`GQL232`).
  final int? maxDepth;

  /// The most aliases in an operation, applied by `MaxAliasesRule`.
  final int? maxAliases;

  /// The most directives in an operation, applied by `MaxDirectivesRule`.
  final int? maxDirectives;

  /// The highest field cost or type cost of an operation, applied by the
  /// cost step of the pipeline (`GQL238`).
  final double? maxCost;

  /// The list size the cost step assumes for a list with no slicing
  /// argument or `@listSize`.
  final int defaultListSize;

  @override
  bool operator ==(Object other) =>
      other is ServerLimits &&
      other.maxDocumentLength == maxDocumentLength &&
      other.maxTokens == maxTokens &&
      other.maxDepth == maxDepth &&
      other.maxAliases == maxAliases &&
      other.maxDirectives == maxDirectives &&
      other.maxCost == maxCost &&
      other.defaultListSize == defaultListSize;

  @override
  int get hashCode => Object.hash(
    maxDocumentLength,
    maxTokens,
    maxDepth,
    maxAliases,
    maxDirectives,
    maxCost,
    defaultListSize,
  );
}
