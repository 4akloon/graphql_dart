import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// Writes the results of a subscription as a graphql-sse event stream in
/// distinct connections mode: one `next` event per result, then `complete`.
final class EventStreamWriter {
  /// Creates the writer.
  const EventStreamWriter();

  /// The bytes of the event stream for [results]; it is lazy, and cancelling
  /// it, or completing [abortTrigger], cancels [results].
  Stream<List<int>> write(
    Stream<ExecutionResult> results,
    Future<void>? abortTrigger,
  ) {
    late StreamController<List<int>> controller; // Set below, read by onListen.
    StreamSubscription<ExecutionResult>? subscription;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = results.listen(
          (result) => controller.add(
            utf8.encode(
              'event: next\ndata: ${jsonEncode(result.toJson().toJson())}\n\n',
            ),
          ),
          onError: controller.addError,
          onDone: () {
            controller.add(utf8.encode('event: complete\ndata: \n\n'));
            controller.close();
          },
        );
        abortTrigger?.then((_) {
          subscription?.cancel();
          controller.close();
        });
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
