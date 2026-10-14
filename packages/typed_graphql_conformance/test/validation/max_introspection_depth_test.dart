import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/MaxIntrospectionDepthRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const MaxIntrospectionDepthRule());

  group('Validate: Max introspection nodes rule', () {
    test('default introspection query', () {
      expect(port.errors(const IntrospectionQuery().text), isEmpty);
    });

    test('all options introspection query', () {
      expect(
        port.errors(
          const IntrospectionQuery(
            includesSpecifiedByUrl: true,
            includesDirectiveIsRepeatable: true,
            includesSchemaDescription: true,
            includesInputValueDeprecation: true,
          ).text,
        ),
        isEmpty,
      );
    });

    test('3 flat fields introspection query', () {
      expect(
        port.errors('''
    {
      __type(name: "Query") {
        trueFields: fields(includeDeprecated: true) {
          name
        }
        falseFields: fields(includeDeprecated: false) {
          name
        }
        omittedFields: fields {
          name
        }
      }
    }
    '''),
        isEmpty,
      );
    });

    test('3 fields deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 interfaces deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          interfaces {
            interfaces {
              interfaces {
                name
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 possibleTypes deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          possibleTypes {
            possibleTypes {
              possibleTypes {
                name
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 inputFields deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          inputFields {
            type {
              inputFields {
                type {
                  inputFields {
                    type {
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query from multiple __schema', () {
      expect(
        port.errors('''
    {
      one: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      two: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      three: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
          'Maximum introspection depth exceeded @ 18:7',
          'Maximum introspection depth exceeded @ 33:7',
        ],
      );
    });

    test('3 fields deep introspection query from __type', () {
      expect(
        port.errors('''
    {
      __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query from multiple __type', () {
      expect(
        port.errors('''
    {
      one: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      two: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      three: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
          'Maximum introspection depth exceeded @ 18:7',
          'Maximum introspection depth exceeded @ 33:7',
        ],
      );
    });

    test('1 fields deep with 3 fields introspection query', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              oneFields: fields {
                name
              }
              twoFields: fields {
                name
              }
              threeFields: fields {
                name
              }
            }
          }
        }
      }
    }
    '''),
        isEmpty,
      );
    });

    test('3 fields deep from varying parents introspection query', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              fields {
                type {
                  ofType {
                    fields {
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query with inline fragments', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ... on __Type {
            fields {
              type {
                ... on __Type {
                  ofType {
                    fields {
                      type {
                        ... on __Type {
                          fields {
                            name
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query with fragments', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...One
        }
      }
    }

    fragment One on __Type {
      fields {
        type {
          ...Two
        }
      }
    }

    fragment Two on __Type {
      fields {
        type {
          ...Three
        }
      }
    }

    fragment Three on __Type {
      fields {
        name
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep inside inline fragment on query', () {
      expect(
        port.errors('''
    {
      ... {
        __schema { types { fields { type { fields { type { fields { name } } } } } } }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 4:9',
        ],
      );
    });

    test('opts out if fragment is missing', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...Missing
        }
      }
    }
    '''),
        isEmpty,
      );
    });

    test("doesn't infinitely recurse on fragment cycle", () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...Cycle
        }
      }
    }
    fragment Cycle on __Type {
      ...Cycle
    }
    '''),
        isEmpty,
      );
    });
  });
}
