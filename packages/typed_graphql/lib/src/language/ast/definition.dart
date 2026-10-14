import 'node.dart';

/// A top-level definition of a [Document]: executable, type system or type
/// system extension (spec §2.2).
///
/// Not sealed: its families are, so a `switch` covers
/// `ExecutableDefinition`, `TypeSystemDefinition` and
/// `TypeSystemExtension`.
///
/// {@category language}
abstract class const Definition({super.start, super.end}) extends Node {
  /// Creates a definition spanning `start` to `end`.
  this;
}
