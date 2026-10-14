import 'package:test/test.dart';

import 'signature.dart';

void main() {
  test('reads the name and the parameters of a method', () {
    final signature = Signature('  int add(int a, int b) {');
    expect(signature.isCallable, isTrue);
    expect(signature.name, 'add');
    expect(signature.parameterCount, 2);
  });

  test('counts named and optional parameters with their defaults', () {
    expect(
      Signature('  void f(int a, {required int b, List<int> c = const []}) {')
          .parameterCount,
      3,
    );
    expect(
      Signature('  void f(int a, [int b = 0, int c = 1, int d]) {')
          .parameterCount,
      4,
    );
  });

  test('counts parameters over several lines with a trailing comma', () {
    expect(
      Signature(
        '  void f(\n'
        '    Map<String, int> a,\n'
        '    void Function(int x, int y) b, {\n'
        '    int c = 1,\n'
        '  }) {',
      ).parameterCount,
      3,
    );
  });

  test('reads getters, setters, operators and generic methods', () {
    expect(Signature('  int get size => 1;').name, 'size');
    expect(Signature('  set size(int value) {').name, 'size=');
    expect(
      Signature('  bool operator ==(Object other) =>').name,
      'operator ==',
    );
    expect(Signature('  void operator []=(int i, int v) {').isCallable, isTrue);
    expect(Signature('  T first<T>(List<T> items) {').name, 'first');
    expect(Signature('  (int, int) pair() =>').name, 'pair');
  });

  test('reads a primary constructor body as this', () {
    expect(Signature('  this : assert(x > 0);').name, 'this');
    expect(Signature('  this {').name, 'this');
  });

  test('a field is not callable, even with a closure or a record type', () {
    for (final line in [
      '  static final RegExp pattern = RegExp(r"x");',
      '  final List<({int a, int b})> items = [];',
      '  final int Function(int) twice = (x) => x * 2;',
      '  static const values = {',
      '  final int count;',
    ]) {
      expect(Signature(line).isCallable, isFalse, reason: line);
    }
    expect(Signature('  final List<({int a})> items = [];').name, 'items');
  });
}
