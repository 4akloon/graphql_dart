import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import 'completion_site.dart';
import 'error_log.dart';
import 'execution_options.dart';
import 'graphql_exception.dart';
import 'response_path.dart';

/// Makes the errors of an execution (spec 7): the library's own, with their
/// `GQL3xx` code, and those user code threw, masked or not and offered to
/// `ExecutionOptions.onError`; then records them in the [log].
final class ErrorReporter {
  /// Reports under [options].
  ErrorReporter(this.options) : log = ErrorLog(options.errorBehavior);

  /// The settings of the execution.
  final ExecutionOptions options;

  /// Where errors go.
  final ErrorLog log;

  /// Records an error the library makes at [site].
  void fieldError(DiagnosticCode code, String message, CompletionSite site) =>
      log.record(
        _coded(code, message, site.path, site.plan.nodes),
        site.path.orderKey(),
      );

  /// Ends the execution with an error the library makes at [site].
  void halt(DiagnosticCode code, String message, CompletionSite site) =>
      log.halt(_coded(code, message, site.path, site.plan.nodes));

  /// Records a coercion [problem] found at [path], about the field [nodes].
  void problem(
    CoercionProblem problem,
    ResponsePath? path,
    List<Field> nodes,
  ) {
    final code = problem.code ?? DiagnosticCode.invalidArgumentValue;
    final reported = GraphQLError(
      '${problem.message}${problem.where}',
      locations: switch (problem.node) {
        final node? => _locations([node]),
        null => _locations(nodes),
      },
      path: path?.toList(),
      extensions: problem.extensions ?? _codeOf(code),
    );
    final thrown = problem.thrown;
    log.record(
      thrown == null
          ? reported
          : hooked(thrown.error, thrown.stackTrace, reported),
      path?.orderKey() ?? const [],
    );
  }

  /// Records [error], thrown by user code at [site].
  void thrown(Object error, StackTrace stackTrace, CompletionSite site) {
    final path = site.path;
    final nodes = site.plan.nodes;
    log.record(
      hooked(error, stackTrace, _reportedFor(error, path, nodes)),
      path.orderKey(),
    );
  }

  /// [reported] after `ExecutionOptions.onError` has seen it: the hook's
  /// replacement, [reported] itself, or the masked error when the hook
  /// throws.
  GraphQLError hooked(
    Object error,
    StackTrace stackTrace,
    GraphQLError reported,
  ) {
    final hook = options.onError;
    if (hook == null) {
      return reported;
    }
    try {
      return hook(error, stackTrace, reported) ?? reported;
    } on Object {
      return GraphQLError(
        _masked,
        locations: reported.locations,
        path: reported.path,
        extensions: _codeOf(DiagnosticCode.unexpectedError),
      );
    }
  }

  static const String _masked = 'Unexpected error.';

  GraphQLError _reportedFor(
    Object error,
    ResponsePath path,
    List<Field> nodes,
  ) => switch (error) {
    GraphQLException(:final message, :final extensions) => GraphQLError(
      message,
      locations: _locations(nodes),
      path: path.toList(),
      extensions: extensions,
    ),
    _ => _coded(
      DiagnosticCode.unexpectedError,
      options.maskErrors ? _masked : error.toString(),
      path,
      nodes,
    ),
  };

  GraphQLError _coded(
    DiagnosticCode code,
    String message,
    ResponsePath path,
    List<Field> nodes,
  ) => GraphQLError(
    message,
    locations: _locations(nodes),
    path: path.toList(),
    extensions: _codeOf(code),
  );

  JsonObject _codeOf(DiagnosticCode code) =>
      JsonObject({'code': JsonString(code.id)});

  List<SourceLocation> _locations(List<Node> nodes) {
    final source = options.source;
    if (source == null) {
      return const [];
    }
    return [for (final node in nodes) source.locationOf(node.start)];
  }
}
