import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// A random schema that is valid by construction, and the SDL it was built
/// from (R10.4).
///
/// The random schemas of the round-trip fuzzer use random type names, so
/// they almost never validate; the operation fuzzers need a schema with
/// every kind of type, wrapper, required argument and `@oneOf` input
/// object. Input objects refer only to earlier ones, so no input cycle can
/// arise; an object copies the fields of the one interface it implements.
final class RandomValidSchema {
  /// Draws from [random]; with [includesCostDirectives], some list fields
  /// get slicing arguments and a `@listSize` (IBM cost draft). A generator
  /// bug is a [StateError] that starts with [replay], the hint to rerun the
  /// case (`FuzzBudget.replay`).
  RandomValidSchema(
    this.random, {
    this.includesCostDirectives = false,
    this.replay = '',
  });

  /// How to replay the case, at the start of a [StateError] message.
  final String replay;

  /// The random source.
  final Random random;

  /// Whether the schema includes the cost directives and uses `@listSize`.
  final bool includesCostDirectives;

  static const List<String> _builtInScalars = [
    'Int',
    'Float',
    'String',
    'Boolean',
    'ID',
  ];

  final StringBuffer _sdl = StringBuffer();
  final List<String> _scalars = [..._builtInScalars];
  final List<String> _enums = [];
  final List<String> _inputs = [];
  final List<String> _outputs = [];

  /// The SDL text and the validated schema; a schema that does not
  /// validate is a bug of this generator and fails.
  ({String sdl, ValidSchema schema}) build() {
    _writeScalarsAndEnums();
    _writeInputs();
    final objectNames = [
      'Query',
      for (var i = 0, n = random.nextInt(4); i < n; i++) 'Obj$i',
    ];
    final interfaceNames = [
      for (var i = 0, n = random.nextInt(3); i < n; i++) 'Ifc$i',
    ];
    final unionNames = [
      for (var i = 0, n = random.nextInt(3); i < n; i++) 'Uni$i',
    ];
    _outputs.addAll([
      ..._scalars,
      ..._enums,
      ...objectNames,
      ...interfaceNames,
      ...unionNames,
    ]);
    final interfaceFields = _writeInterfaces(interfaceNames);
    _writeObjects(objectNames, interfaceFields);
    for (final name in unionNames) {
      final members = (List.of(objectNames)..shuffle(random)).take(
        1 + random.nextInt(objectNames.length),
      );
      _sdl.writeln('union $name = ${members.join(' | ')}');
    }
    final sdl = _sdl.toString();
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final built = SchemaBuilder(
      includesCostDirectives: includesCostDirectives,
    ).fromSdl(document);
    if (built is! BuildSuccess) {
      throw StateError(
        '$replay generated SDL does not build: ${built.diagnostics}\n'
        '$sdl',
      );
    }
    final validated = const SchemaValidator().validate(built.schema);
    if (validated is! ValidSchema) {
      throw StateError(
        '$replay generated SDL is invalid: ${validated.diagnostics}\n'
        '$sdl',
      );
    }
    return (sdl: sdl, schema: validated);
  }

  void _writeScalarsAndEnums() {
    for (var i = 0, n = random.nextInt(3); i < n; i++) {
      _sdl.writeln('scalar Scalar$i');
      _scalars.add('Scalar$i');
    }
    for (var i = 0, n = random.nextInt(3); i < n; i++) {
      final values = [
        for (var j = 0, m = 1 + random.nextInt(3); j < m; j++) 'E${i}V$j',
      ];
      _sdl.writeln('enum Enum$i { ${values.join(' ')} }');
      _enums.add('Enum$i');
    }
  }

  void _writeInputs() {
    for (var i = 0, n = random.nextInt(4); i < n; i++) {
      final isOneOf = random.nextInt(4) == 0;
      final pool = [..._scalars, ..._enums, ..._inputs];
      final fields = [
        for (var j = 0, m = 1 + random.nextInt(3); j < m; j++)
          'g$j: ${_wrap(pool[random.nextInt(pool.length)], isNullable: isOneOf)}',
      ];
      _sdl.writeln(
        'input In$i${isOneOf ? ' @oneOf' : ''} { ${fields.join(' ')} }',
      );
      _inputs.add('In$i');
    }
  }

  /// The interfaces' fields by name, for the objects that implement them.
  Map<String, List<String>> _writeInterfaces(List<String> names) {
    final fields = <String, List<String>>{};
    for (final name in names) {
      final own = _fields('i${name}_', 1 + random.nextInt(3));
      fields[name] = own;
      _sdl.writeln('interface $name { ${own.join(' ')} }');
    }
    return fields;
  }

  void _writeObjects(
    List<String> names,
    Map<String, List<String>> interfaceFields,
  ) {
    for (final name in names) {
      final interfaces = interfaceFields.keys.toList();
      final implemented = interfaces.isNotEmpty && random.nextBool()
          ? interfaces[random.nextInt(interfaces.length)]
          : null;
      final fields = [
        if (implemented != null) ...interfaceFields[implemented]!,
        ..._fields('f${name}_', implemented == null ? 1 : random.nextInt(3)),
      ];
      final clause = implemented == null ? '' : ' implements $implemented';
      _sdl.writeln('type $name$clause { ${fields.join(' ')} }');
    }
  }

  List<String> _fields(String prefix, int count) => [
    for (var i = 0; i < count; i++) _field('$prefix$i'),
  ];

  String _field(String name) {
    if (includesCostDirectives && random.nextInt(4) == 0) {
      return _slicedField(name);
    }
    return '$name${_arguments()}: ${_wrap(_pickOutput())}';
  }

  // A list field whose `first` and `last` size it, so that
  // `SlicingArgumentsRule` has something to report.
  String _slicedField(String name) =>
      '$name(first: Int, last: Int): [${_pickOutput()}] '
      '@listSize(slicingArguments: ["first", "last"])';

  String _pickOutput() => _outputs[random.nextInt(_outputs.length)];

  /// Zero to two arguments; some required, some with a default.
  String _arguments() {
    final count = random.nextInt(3);
    if (count == 0) {
      return '';
    }
    final pool = [..._scalars, ..._enums, ..._inputs];
    final arguments = [
      for (var i = 0; i < count; i++) _argument(i, pool),
    ];
    return '(${arguments.join(', ')})';
  }

  String _argument(int index, List<String> pool) {
    if (random.nextInt(5) == 0) {
      final withDefault = random.nextBool();
      return withDefault
          ? 'a$index: Int! = ${random.nextInt(9)}'
          : 'a$index: String = "x"';
    }
    return 'a$index: ${_wrap(pool[random.nextInt(pool.length)])}';
  }

  /// [name] as it, non-null, a list or a nested list; with [isNullable],
  /// never non-null (a `@oneOf` field).
  String _wrap(String name, {bool isNullable = false}) {
    if (isNullable) {
      return random.nextBool() ? name : '[$name]';
    }
    return switch (random.nextInt(6)) {
      0 => name,
      1 => '$name!',
      2 => '[$name]',
      3 => '[$name!]!',
      4 => '[$name!]',
      _ => '[[$name]]',
    };
  }
}
