import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the main describe block, from the deep conflicts on); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('deep conflict', () {
      expect(
        port.errors('''
      {
        field {
          x: a
        },
        field {
          x: b
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 6:9 7:11',
        ],
      );
    });

    test('deep conflict with multiple issues', () {
      expect(
        port.errors('''
      {
        field {
          x: a
          y: c
        },
        field {
          x: b
          y: d
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "x" conflict because "a" and "b" are different fields and subfields "y" conflict because "c" and "d" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 5:11 7:9 8:11 9:11',
        ],
      );
    });

    test('does not compare subfields of incompatible parent calls', () {
      expect(
        port.errors('''
      fragment incompatibleParents on Dog {
        parent: mother {
          value: name
        }
        parent: father {
          value: mother { name }
        }
      }
    '''),
        [
          'Fields "parent" conflict because "mother" and "father" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 6:9',
        ],
      );
    });

    test('still compares subfields of each compatible parent-call group', () {
      // Adapted (M4 spec deviation 4): the father is compared with the
      // first mother only, which keeps the work linear, and the conflicts
      // found in one selection set come in discovery order.
      expect(
        port.errors('''
      fragment mixedParents on Dog {
        parent: mother {
          value: name
        }
        parent: mother {
          value: mother { name }
        }
        parent: father { name }
      }
    '''),
        [
          'Fields "parent" conflict because "mother" and "father" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 9:9',
          'Fields "parent" conflict because subfields "value" conflict because "name" and "mother" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 6:9 7:11',
        ],
      );
    });

    test('very deep conflict', () {
      expect(
        port.errors('''
      {
        field {
          deepField {
            x: a
          }
        },
        field {
          deepField {
            x: b
          }
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "deepField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 5:13 8:9 9:11 10:13',
        ],
      );
    });

    test('reports deep conflict to nearest common ancestor', () {
      expect(
        port.errors('''
      {
        field {
          deepField {
            x: a
          }
          deepField {
            x: b
          }
        },
        field {
          deepField {
            y
          }
        }
      }
    '''),
        [
          'Fields "deepField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 4:11 5:13 7:11 8:13',
        ],
      );
    });

    test('reports deep conflict to nearest common ancestor in fragments', () {
      expect(
        port.errors('''
      {
        field {
          ...F
        }
        field {
          ...F
        }
      }
      fragment F on T {
        deepField {
          deeperField {
            x: a
          }
          deeperField {
            x: b
          }
        },
        deepField {
          deeperField {
            y
          }
        }
      }
    '''),
        [
          'Fields "deeperField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 12:11 13:13 15:11 16:13',
        ],
      );
    });

    test('reports deep conflict in nested fragments', () {
      expect(
        port.errors('''
      {
        field {
          ...I
        }
        field {
          ...F
        }
      }
      fragment F on T {
        x: a
        ...G
      }
      fragment G on T {
        y: c
      }
      fragment I on T {
        y: d
        ...J
      }
      fragment J on T {
        x: b
      }
    '''),
        [
          'Fields "field" conflict because subfields "y" conflict because "d" and "c" are different fields and subfields "x" conflict because "b" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 18:9 22:9 6:9 15:9 11:9',
        ],
      );
    });

    test('reports deep conflict after nested fragments', () {
      expect(
        port.errors('''
      fragment F on T {
        ...G
      }
      fragment G on T {
        ...H
      }
      fragment H on T {
        x: a
      }
      {
        x: b
        ...F
      }
    '''),
        [
          'Fields "x" conflict because "b" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 12:9 9:9',
        ],
      );
    });

    test('ignores unknown fragments', () {
      expect(
        port.errors('''
      {
        field
        ...Unknown
        ...Known
      }

      fragment Known on T {
        field
        ...OtherUnknown
      }
    '''),
        isEmpty,
      );
    });
  });
}
