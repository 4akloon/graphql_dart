import 'dart_writer.dart';

/// Writes the `_read` factory of a generated class: the class built from the
/// JSON and the context.
///
/// {@category codegen}
final class ReaderFactoryWriter {
  /// Creates the writer.
  const ReaderFactoryWriter();

  static const List<String> _parameters = <String>[
    'graphql.JsonObject json',
    'client.DataContext context',
  ];

  /// Writes `factory [className]._read(...)` that builds the class from the
  /// named [arguments], pairs of label and value expression.
  ///
  /// The parameters stay on the head's line when they fit; a conditional
  /// value breaks before its `?` and `:`.
  void write(
    DartWriter writer,
    String className,
    List<(String, String)> arguments,
  ) {
    // A call without arguments is constant, or `prefer_const_constructors`
    // fires on the generated code.
    final String callee = arguments.isEmpty ? 'const $className' : className;
    final String head = 'factory $className._read(${_parameters.join(', ')})';
    final List<String> labelled = [
      for (final (String label, String value) in arguments) '$label: $value',
    ];
    if (!writer.fits('$head =>')) {
      writer.line('factory $className._read(');
      writer.indented(() {
        for (final String parameter in _parameters) {
          writer.line('$parameter,');
        }
      });
      _call(writer, ') => $callee(', labelled, arguments);
      return;
    }
    if (writer.fits('$head => $callee(${labelled.join(', ')});')) {
      writer.line('$head => $callee(${labelled.join(', ')});');
      return;
    }
    writer.line('$head =>');
    writer.indented(
      () => writer.indented(
        () => _call(writer, '$callee(', labelled, arguments),
      ),
    );
  }

  void _call(
    DartWriter writer,
    String open,
    List<String> labelled,
    List<(String, String)> arguments,
  ) {
    if (writer.fits('$open${labelled.join(', ')});')) {
      writer.line('$open${labelled.join(', ')});');
      return;
    }
    writer.line(open);
    writer.indented(() {
      for (final (int index, String argument) in labelled.indexed) {
        _argument(writer, argument, arguments[index].$2);
      }
    });
    writer.line(');');
  }

  void _argument(DartWriter writer, String argument, String value) {
    final int question = value.indexOf(' ? ');
    if (writer.fits('$argument,') || question < 0) {
      writer.line('$argument,');
      return;
    }
    final int colon = value.lastIndexOf(' : ');
    final String label = argument.substring(0, argument.length - value.length);
    writer.line('$label${value.substring(0, question)}');
    writer.indented(() {
      writer.indented(() {
        writer.line(value.substring(question + 1, colon));
        writer.line('${value.substring(colon + 1)},');
      });
    });
  }
}
