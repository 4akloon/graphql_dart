import 'package:test/test.dart';

import 'blanked_code.dart';
import 'nesting_meter.dart';

void main() {
  List<int> deeperThan3(String body) => NestingMeter(
    BlankedCode('void f() {\n$body}\n'),
  ).linesDeeperThan(3);

  test('counts if, for, while, switch and try', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    while (true) {\n'
        '      try {\n'
        '        if (a) {\n'
        '        }\n'
        '      } on E catch (e) {\n'
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      [4],
    );
  });

  test('does not count an else-if chain as deeper', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        '      if (b) {\n'
        '      } else if (c) {\n'
        '      } else {\n'
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      isEmpty,
    );
  });

  test('counts a switch expression but not closures or literals', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        '      list.forEach((x) {\n'
        '        final m = {1: 2};\n'
        '        return switch (x) {\n'
        '          _ => () { if (y) {} },\n'
        '        };\n'
        '      });\n'
        '    }\n'
        '  }\n',
      ),
      [6],
    );
  });

  test('does not read a map pattern as a block', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        "      if (m case {'k': 1}) {\n"
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      isEmpty,
    );
  });
}
