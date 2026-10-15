import 'package:typed_graphql/typed_graphql.dart';

/// Sees an error user code threw, before it is recorded.
///
/// [reported] is the error that would be recorded: masked, or the
/// `GraphQLException` as it is, with its path and locations. A non-null
/// result replaces it; null keeps it. A hook that throws makes the masked
/// error the recorded one.
///
/// {@category execution}
typedef ErrorHook = GraphQLError? Function(
  Object error,
  StackTrace stackTrace,
  GraphQLError reported,
);
