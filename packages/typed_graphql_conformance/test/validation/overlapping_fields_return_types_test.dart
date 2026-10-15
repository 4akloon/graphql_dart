import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the describe block 'return types must be unambiguous'); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    group('return types must be unambiguous', () {
      final boxes = port.withSchema('''
      interface SomeBox {
        deepBox: SomeBox
        unrelatedField: String
      }

      type StringBox implements SomeBox {
        scalar: String
        deepBox: StringBox
        unrelatedField: String
        listNode: [Node]
        listStringBox: [StringBox]
        stringBox: StringBox
        intBox: IntBox
      }

      type IntBox implements SomeBox {
        scalar: Int
        deepBox: IntBox
        unrelatedField: String
        node: Node
        listStringBox: [StringBox]
        stringBox: StringBox
        intBox: IntBox
      }

      interface NonNullStringBox1 {
        scalar: String!
      }

      type NonNullStringBox1Impl implements SomeBox & NonNullStringBox1 {
        scalar: String!
        unrelatedField: String
        deepBox: SomeBox
      }

      interface NonNullStringBox2 {
        scalar: String!
      }

      type NonNullStringBox2Impl implements SomeBox & NonNullStringBox2 {
        scalar: String!
        unrelatedField: String
        deepBox: SomeBox
      }

      type Connection {
        edges: [Edge]
      }

      type Edge {
        node: Node
      }

      type Node {
        id: ID
        name: String
      }

      type Query {
        someBox: SomeBox
        connection: Connection
      }
    ''');

      test('conflicting return types which potentially overlap', () {
        // This is invalid since an object could potentially be both the Object
        // type IntBox and the interface type NonNullStringBox1. While that
        // condition does not exist in the current schema, the schema could
        // expand in the future to allow this. Thus it is invalid.
        expect(
          boxes.errors('''
          {
            someBox {
              ...on IntBox {
                scalar
              }
              ...on NonNullStringBox1 {
                scalar
              }
            }
          }
        '''),
          [
            'Fields "scalar" conflict because they return conflicting types "Int" and "String!". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('compatible return shapes on different return types', () {
        // In this case `deepBox` returns `SomeBox` in the first usage, and
        // `StringBox` in the second usage. These return types are not the same!
        // however this is valid because the return *shapes* are compatible.
        expect(
          boxes.errors('''
          {
            someBox {
              ... on SomeBox {
                deepBox {
                  unrelatedField
                }
              }
              ... on StringBox {
                deepBox {
                  unrelatedField
                }
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('disallows differing return types despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                scalar
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
          [
            'Fields "scalar" conflict because they return conflicting types "Int" and "String". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('does not compare subfields after a response-type conflict', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on StringBox {
                parent: listNode { value: name }
              }
              ... on IntBox {
                parent: node { value: id }
              }
            }
          }
        '''),
          [
            'Fields "parent" conflict because they return conflicting types "[Node]" and "Node". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('reports correctly when a non-exclusive follows an exclusive', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                deepBox {
                  ...X
                }
              }
            }
            someBox {
              ... on StringBox {
                deepBox {
                  ...Y
                }
              }
            }
            memoed: someBox {
              ... on IntBox {
                deepBox {
                  ...X
                }
              }
            }
            memoed: someBox {
              ... on StringBox {
                deepBox {
                  ...Y
                }
              }
            }
            other: someBox {
              ...X
            }
            other: someBox {
              ...Y
            }
          }
          fragment X on SomeBox {
            scalar
          }
          fragment Y on SomeBox {
            scalar: unrelatedField
          }
        '''),
          [
            'Fields "other" conflict because subfields "scalar" conflict because "scalar" and "unrelatedField" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 31:13 39:13 34:13 42:13',
          ],
        );
      });

      test(
        'disallows differing return type nullability despite no overlap',
        () {
          expect(
            boxes.errors('''
          {
            someBox {
              ... on NonNullStringBox1 {
                scalar
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
            [
              'Fields "scalar" conflict because they return conflicting types "String!" and "String". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
            ],
          );
        },
      );

      test('disallows differing return type list despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: listStringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: stringBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because they return conflicting types "[StringBox]" and "StringBox". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 10:17',
          ],
        );

        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: listStringBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because they return conflicting types "StringBox" and "[StringBox]". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 10:17',
          ],
        );
      });

      test('disallows differing subfields', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  val: scalar
                  val: unrelatedField
                }
              }
              ... on StringBox {
                box: stringBox {
                  val: scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "val" conflict because "scalar" and "unrelatedField" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 6:19 7:19',
          ],
        );
      });

      test('disallows differing deep return types despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: intBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because subfields "scalar" conflict because they return conflicting types "String" and "Int". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 6:19 10:17 11:19',
          ],
        );
      });

      test('allows non-conflicting overlapping types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                scalar: unrelatedField
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('same wrapped scalar return types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ...on NonNullStringBox1 {
                scalar
              }
              ...on NonNullStringBox2 {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('allows inline fragments without type condition', () {
        expect(
          boxes.errors('''
          {
            a
            ... {
              a
            }
          }
        '''),
          isEmpty,
        );
      });

      test('compares deep types including list', () {
        expect(
          boxes.errors('''
          {
            connection {
              ...edgeID
              edges {
                node {
                  id: name
                }
              }
            }
          }

          fragment edgeID on Connection {
            edges {
              node {
                id
              }
            }
          }
        '''),
          [
            'Fields "edges" conflict because subfields "node" conflict because subfields "id" conflict because "name" and "id" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 5:15 6:17 7:19 14:13 15:15 16:17',
          ],
        );
      });

      test('ignores unknown types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ...on UnknownType {
                scalar
              }
              ...on NonNullStringBox2 {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('works for field names that are JS keywords', () {
        const schemaWithKeywords = '''
        type Foo {
          constructor: String
        }

        type Query {
          foo: Foo
        }
      ''';

        expect(
          port.withSchema(schemaWithKeywords).errors('''
          {
            foo {
              constructor
            }
          }
        '''),
          isEmpty,
        );
      });
    });
  });
}
