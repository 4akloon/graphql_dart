import 'package:typed_graphql/typed_graphql.dart';

/// A generated class that writes itself as JSON: data, fragments, input
/// objects and variables.
///
/// {@category operations}
abstract interface class DataObject {
  /// The JSON of this value; for data, the response JSON it was read from,
  /// up to member order and the `__typename` the generator added.
  JsonObject toJson();
}
