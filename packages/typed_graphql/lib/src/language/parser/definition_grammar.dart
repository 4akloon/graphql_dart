import '../ast/definition.dart';

/// A definition production outside the September2025 grammar: the
/// parser's extension point for working-draft and experimental grammar
/// (R1.4). `DefinitionParser` asks every registered grammar before the
/// base productions, so a new one never edits them.
abstract interface class DefinitionGrammar {
  /// Whether the definition at the cursor belongs to this grammar.
  bool startsDefinition();

  /// Parses that definition; a syntax error fails through the cursor.
  Definition definition();
}
