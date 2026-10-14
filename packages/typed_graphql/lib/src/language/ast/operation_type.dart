/// The type of an operation (spec §2.3): its keyword is its [name].
///
/// {@category language}
enum OperationType {
  /// `query`: a read-only fetch.
  query,

  /// `mutation`: a write followed by a fetch.
  mutation,

  /// `subscription`: a long-lived request that fetches on events.
  subscription,
}
