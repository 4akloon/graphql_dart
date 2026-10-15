import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/operation_text.dart';

/// Writes the persisted-operations manifest (R7.9): every operation's id,
/// name, type and the text its class sends.
final class PersistedManifest {
  /// Creates the writer; [text] gives the documents and their hashes.
  const PersistedManifest(this.text);

  /// The writer of document texts, shared with the operation classes.
  final OperationText text;

  /// The manifest of the operations in [document], sorted by name, with a
  /// final line break.
  String of(Document document) {
    final operations = [
      for (final definition in document.definitions)
        if (definition is OperationDefinition) definition,
    ]..sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
    final manifest = <String, Object?>{
      'format': 'apollo-persisted-query-manifest',
      'version': 1,
      'operations': [
        for (final operation in operations) _entry(operation),
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  }

  Map<String, Object?> _entry(OperationDefinition operation) {
    final String body = text.of(operation);
    return {
      'id': text.hashOf(body),
      'name': _nameOf(operation),
      'type': operation.operation.name,
      'body': body,
    };
  }

  String _nameOf(OperationDefinition operation) => operation.name?.value ?? '';
}
