/// Valid inputs of the single-element parser entry points, which the
/// hostile-text fuzzer mutates: kitchen sinks fail them at the first token.
abstract final class ElementCorpora {
  /// Values, with and without variables.
  static const List<String> values = [
    r'[1, {a: $b, c: "x"}, ENUM]',
    '"""b"""',
    '[[1.5e3, -0], [], {}]',
    r'{a: {b: [true, false, null]}, c: "\u00e9\n"}',
    'ENUM',
  ];

  /// Values without variables, which a constant value allows.
  static const List<String> constValues = [
    '[1, {a: "x"}, ENUM]',
    '"""b"""',
    '{a: {b: [true, null]}}',
  ];

  /// Type references.
  static const List<String> types = ['[[Int!]!]', 'T!', '[T]', 'Name'];

  /// Schema coordinates.
  static const List<String> coordinates = [
    'Type.field(arg:)',
    '@dir(arg:)',
    '@dir',
    'Type',
    'Type.field',
    'Enum.VALUE',
  ];
}
