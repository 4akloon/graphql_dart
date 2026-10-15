import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/class_names.dart';
import '../plan/operation_text.dart';
import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';

/// Writes the class of an operation (spec §7 "Operation classes and
/// metadata", R7.9): its document, its variables and how it reads its data.
///
/// {@category codegen}
final class OperationEmitter {
  /// Creates the emitter; [text] writes the documents sent.
  const OperationEmitter(this.text);

  /// The writer of document texts.
  final OperationText text;

  static const ClassNames _names = ClassNames();

  /// Writes the class of [operation], whose data class is named
  /// [dataName], to [writer].
  void emit(OperationDefinition operation, String dataName, DartWriter writer) {
    final String operationName = operation.name?.value ?? '';
    final String kind = operation.operation.name;
    final String name = _names.operation(operationName, operation.operation);
    final String base = 'client.GraphQL${const DartNames().capitalized(kind)}';
    final bool hasVariables = operation.variableDefinitions.isNotEmpty;
    writer.doc('The $kind `$operationName`.');
    final String header = 'final class $name';
    final String extension = 'extends $base<$dataName> {';
    if (writer.fits('$header $extension')) {
      writer.line('$header $extension');
    } else {
      writer.line(header);
      writer.indented(() => writer.indented(() => writer.line(extension)));
    }
    writer.indented(() {
      _constructor(writer, name, kind, hasVariables);
      writer.line();
      _document(writer, operation, operationName);
      if (hasVariables) {
        writer.line();
        writer.doc('The variables the $kind is sent with.');
        writer.line('final ${_names.variables(operationName)} variables;');
      }
      _overrides(writer, dataName, hasVariables);
    });
    writer.line('}');
  }

  void _overrides(DartWriter writer, String dataName, bool hasVariables) {
    final overrides = [
      (
        'client.OperationDocument get document',
        'operationDocument',
      ),
      (
        'graphql.JsonObject get variablesJson',
        hasVariables ? 'variables.toJson()' : 'graphql.JsonObject(const {})',
      ),
      (
        'graphql.DecodeResult<$dataName> decodeData(graphql.JsonObject data)',
        hasVariables
            ? '$dataName.decode(data, variables: variablesJson)'
            : '$dataName.decode(data)',
      ),
    ];
    for (final (head, expression) in overrides) {
      writer.line();
      writer.line('@override');
      writer.arrow(head, expression);
    }
  }

  void _constructor(
    DartWriter writer,
    String name,
    String kind,
    bool hasVariables,
  ) {
    if (hasVariables) {
      writer.doc('Creates the $kind with its [variables].');
      writer.line('const $name(this.variables);');
    } else {
      writer.doc('Creates the $kind.');
      writer.line('const $name();');
    }
  }

  void _document(
    DartWriter writer,
    OperationDefinition operation,
    String operationName,
  ) {
    const literal = DartStringLiteral();
    final String document = text.of(operation);
    final String hash = sha256.convert(utf8.encode(document)).toString();
    writer.doc('The document of `$operationName` as it is sent.');
    writer.line('static const client.OperationDocument operationDocument =');
    writer.indented(() {
      writer.indented(() {
        writer.line('client.OperationDocument(');
        writer.indented(() {
          writer.line('name: ${literal.of(operationName)},');
          writer.line(
            'type: graphql.OperationType.${operation.operation.name},',
          );
          writer.line('text: ${literal.of(document)},');
          writer.line('sha256:');
          writer.indented(() => writer.line('${literal.of(hash)},'));
        });
        writer.line(');');
      });
    });
  }
}
