import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The text of a `GQL238` refusal: `MaxCostRule`'s message to the character.
///
/// The core's `OperationSubject` and `CostNumber` are not exported, so their
/// wording is reproduced here.
@internal
final class CostMessage {
  /// Creates the writer.
  const CostMessage();

  // Beyond 1e15 the platforms print doubles differently; the exponential
  // form is the same everywhere (as the core's `CostNumber`).
  static const double _largest = 1000000000000000;

  /// The message for [operation] costing [cost] against [maxCost].
  String of(OperationDefinition operation, OperationCost cost, double maxCost) {
    final subject = switch (operation.name) {
      final name? => 'The operation "${name.value}"',
      null => 'The anonymous operation',
    };
    return '$subject has a field cost of ${_number(cost.fieldCost)} and a '
        'type cost of ${_number(cost.typeCost)}, more than the maximum of '
        '${_number(maxCost)}.';
  }

  // A negative zero prints as "0" on every platform.
  String _number(double value) => switch (value == 0 ? 0.0 : value) {
    final number when !number.isFinite => number.toString(),
    final number when number.abs() >= _largest =>
      number.toStringAsExponential(),
    final number when number == number.truncateToDouble() =>
      number.toStringAsFixed(0),
    final number => number.toString(),
  };
}
