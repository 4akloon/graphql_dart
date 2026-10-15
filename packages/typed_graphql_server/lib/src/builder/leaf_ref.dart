import 'input_ref.dart';
import 'output_ref.dart';

/// A reference to a scalar or enum type, which serves as an output and as
/// an input type (spec 3.3).
///
/// {@category builder}
abstract interface class LeafRef<T> implements OutputRef<T>, InputRef<T> {
  /// This type without the non-null wrapper.
  @override
  LeafRef<T?> get nullable;
}
