import 'boolean_codec.dart';
import 'float_codec.dart';
import 'id_codec.dart';
import 'int_codec.dart';
import 'scalar_codec.dart';
import 'string_codec.dart';

/// The codecs of the scalar types by name (R2.9): the five built-in ones
/// and those a server or a client adds for its custom scalars.
///
/// A registry is immutable: [withCodec] gives a new one.
///
/// {@category scalars}
final class ScalarCodecs {
  /// A registry of the five built-in codecs.
  const ScalarCodecs() : _codecs = _builtIns;

  const ScalarCodecs._(this._codecs);

  static const Map<String, ScalarCodec<Object>> _builtIns = {
    'Int': IntCodec(),
    'Float': FloatCodec(),
    'String': StringCodec(),
    'Boolean': BooleanCodec(),
    'ID': IdCodec(),
  };

  // Only for lookups, never iterated.
  final Map<String, ScalarCodec<Object>> _codecs;

  /// This registry with [codec] for the scalar named [name], replacing the
  /// codec it had. A built-in codec cannot be replaced: an
  /// [ArgumentError].
  ScalarCodecs withCodec(String name, ScalarCodec<Object> codec) {
    if (_builtIns.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'is a built-in scalar');
    }
    return ScalarCodecs._({..._codecs, name: codec});
  }

  /// The codec of the scalar named [name]; null when there is none.
  ScalarCodec<Object>? codecFor(String name) => _codecs[name];
}
