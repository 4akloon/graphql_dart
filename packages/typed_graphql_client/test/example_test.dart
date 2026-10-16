import 'dart:async';

import 'package:test/test.dart';

import '../example/example.dart' as example;

void main() {
  test('the example prints the query and the three ticks', () async {
    final lines = <String>[];
    await runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    expect(lines, ['hello: world', 'tick: 1', 'tick: 2', 'tick: 3']);
  });
}
