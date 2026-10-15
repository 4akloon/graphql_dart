import 'package:test/test.dart';

import '../support/class_emission.dart';

const _schema = '''
type User { id: ID! }
type Query { user: User }
''';

void main() {
  test('an unconditional and a conditional fragment', () {
    final emission = ClassEmission(_schema, r'''
query Q($a: Boolean!) {
  user {
    ...F1
    ...F2 @include(if: $a)
  }
}
fragment F1 on User { id }
fragment F2 on User { id }
''');
    expect(emission.emit('QDataUserFragments'), r'''
/// The fragments spread on [QDataUser].
final class QDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const QDataUserFragments({required this.f1, this.f2});

  factory QDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => QDataUserFragments(
    f1: F1.codec.read(json, context),
    f2: context.flag('a') ? F2.codec.read(json, context) : null,
  );

  /// The fragment `F1`.
  final F1 f1;

  /// The fragment `F2`; null when `@include` or `@skip` left it out.
  final F2? f2;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...f1.toJson().fields,
    ...?f2?.toJson().fields,
  });

  @override
  bool operator ==(Object other) =>
      other is QDataUserFragments && other.f1 == f1 && other.f2 == f2;

  @override
  int get hashCode => Object.hashAll([f1, f2]);

  @override
  String toString() => 'QDataUserFragments(f1: $f1, f2: $f2)';
}
''');
  });

  test('a single skipped fragment', () {
    final emission = ClassEmission(_schema, r'''
query Q($b: Boolean!) { user { ...F1 @skip(if: $b) } }
fragment F1 on User { id }
''');
    expect(emission.emit('QDataUserFragments'), r'''
/// The fragments spread on [QDataUser].
final class QDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const QDataUserFragments({this.f1});

  factory QDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => QDataUserFragments(
    f1: !context.flag('b') ? F1.codec.read(json, context) : null,
  );

  /// The fragment `F1`; null when `@include` or `@skip` left it out.
  final F1? f1;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({...?f1?.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is QDataUserFragments && other.f1 == f1;

  @override
  int get hashCode => f1.hashCode;

  @override
  String toString() => 'QDataUserFragments(f1: $f1)';
}
''');
  });

  test('a fragment spread under two conditions joins them with ||', () {
    final emission = ClassEmission(_schema, r'''
query Q($a: Boolean!, $b: Boolean!, $c: Boolean!) {
  user {
    ...F1 @include(if: $c)
    ... @include(if: $a) { ...F1 @skip(if: $b) }
    ...F2 @include(if: $c)
    ... @include(if: $a) { ...F2 @skip(if: $b) }
  }
}
fragment F1 on User { id }
fragment F2 on User { id }
''');
    final text = emission.emit('QDataUserFragments');
    expect(
      text,
      contains(
        "f1: context.flag('c') || (context.flag('a') && !context.flag('b'))\n",
      ),
    );
  });
}
