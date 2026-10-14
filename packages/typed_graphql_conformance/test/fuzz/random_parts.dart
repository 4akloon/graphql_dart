import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// Random names, values, types and directives for the round-trip fuzzer:
/// only what a parser reads back as an equivalent tree.
final class RandomParts {
  /// Draws from [random].
  RandomParts(this.random);

  /// The random source.
  final Random random;

  static const String _nameStart =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
  static const String _nameContinue = '${_nameStart}0123456789';

  /// Words the grammar gives a meaning somewhere, which stay plain names
  /// everywhere else.
  static const List<String> _keywords = [
    'on',
    'query',
    'mutation',
    'subscription',
    'fragment',
    'schema',
    'scalar',
    'type',
    'interface',
    'union',
    'enum',
    'input',
    'directive',
    'extend',
    'implements',
    'repeatable',
    'true',
    'false',
    'null',
  ];

  /// What strings are made of: quotes, backslashes, line terminators,
  /// control characters and a supplementary character, but no lone
  /// surrogate, which no printed string can hold.
  static const List<String> _stringParts = [
    'a',
    'Z',
    ' ',
    '  ',
    '"',
    '"""',
    r'\',
    '\n',
    '\r\n',
    '\t',
    '\u0001',
    '\u007f',
    'é',
    '\u{1F600}',
  ];

  /// Whether a [percent] chance comes true.
  bool chance(int percent) => random.nextInt(100) < percent;

  /// One of [items].
  T pick<T>(List<T> items) => items[random.nextInt(items.length)];

  /// From [min] to [max] items made by [make].
  List<T> some<T>(int max, T Function() make, {int min = 0}) =>
      List.generate(min + random.nextInt(max - min + 1), (_) => make());

  /// A name; often a keyword, which the grammar must keep a name.
  Name name() {
    if (chance(25)) {
      return Name(pick(_keywords));
    }
    final buffer = StringBuffer(_nameStart[random.nextInt(_nameStart.length)]);
    for (var i = random.nextInt(6); i > 0; i--) {
      buffer.write(_nameContinue[random.nextInt(_nameContinue.length)]);
    }
    return Name(buffer.toString());
  }

  /// A name that is not `on`, which a fragment cannot have (spec §2.8).
  Name fragmentName() => _avoiding(const {'on'});

  /// A name that is not `true`, `false` or `null`: an enum value
  /// (spec §2.9.6).
  Name enumValueName() => _avoiding(const {'true', 'false', 'null'});

  Name _avoiding(Set<String> words) {
    final candidate = name();
    return words.contains(candidate.value)
        ? Name('${candidate.value}_')
        : candidate;
  }

  /// A value; a variable only when not [isConst]. Lists and objects nest
  /// at most three levels.
  Value value({required bool isConst, int depth = 0}) {
    Value nested() => value(isConst: isConst, depth: depth + 1);
    return switch (random.nextInt(depth < 3 ? 10 : 8)) {
      0 when !isConst => Variable(name()),
      0 || 1 => IntValue(_integer()),
      2 => FloatValue(_float()),
      3 => string(),
      4 => BooleanValue(random.nextBool()),
      5 => const NullValue(),
      6 || 7 => EnumValue(enumValueName().value),
      8 => ListValue(some(3, nested)),
      _ => ObjectValue(some(3, () => ObjectField(name(), nested()))),
    };
  }

  /// A quoted or block string; a block string only when its value can be
  /// printed as one, as graphql-js's `isPrintableAsBlockString` decides.
  StringValue string() {
    final text = some(6, () => pick(_stringParts)).join();
    final isBlock = chance(40) && const BlockString().isPrintable(text);
    return StringValue(text, isBlock: isBlock);
  }

  /// A description, or none.
  StringValue? description() => chance(30) ? string() : null;

  /// A named, list or non-null type, lists nested at most twice.
  TypeRef type({int depth = 0}) {
    final TypeRef inner = depth < 2 && chance(30)
        ? ListType(type(depth: depth + 1))
        : NamedType(name());
    return chance(40) ? NonNullType(inner) : inner;
  }

  /// Up to two directives with arguments.
  List<Directive> directives({required bool isConst}) => some(
    2,
    () => Directive(name(), arguments: arguments(isConst: isConst)),
  );

  /// Up to three arguments.
  List<Argument> arguments({required bool isConst}) =>
      some(3, () => Argument(name(), value(isConst: isConst)));

  String _integer() {
    final sign = chance(20) ? '-' : '';
    if (chance(20)) {
      return '${sign}0';
    }
    final digits = some(5, () => random.nextInt(10)).join();
    return '$sign${1 + random.nextInt(9)}$digits';
  }

  String _float() {
    final hasFraction = chance(70);
    final hasExponent = !hasFraction || chance(30);
    final fraction = hasFraction
        ? '.${some(3, () => random.nextInt(10), min: 1).join()}'
        : '';
    final exponent = hasExponent
        ? '${pick(['e', 'E'])}${pick(['', '+', '-'])}${random.nextInt(40)}'
        : '';
    return '${_integer()}$fraction$exponent';
  }
}
