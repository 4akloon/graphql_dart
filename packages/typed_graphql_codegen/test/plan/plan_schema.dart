/// The schema the planner tests share.
const planSchema = '''
interface Node { id: ID! }
interface Named { name: String }
interface Entity implements Node { id: ID! }
type User implements Node & Named { id: ID!, name: String, friend: User }
type Bot implements Node { id: ID!, model: String }
type Group implements Named { name: String }
type Admin implements Entity & Node { id: ID!, level: Int }
union Actor = User | Bot
union Thing = User | Group
type Query {
  node: Node
  actor: Actor
  user: User
  named: Named
  thing: Thing
}
''';

/// A query that makes the fixture valid whatever the test needs.
const planNoop = 'query { user { id } }';
