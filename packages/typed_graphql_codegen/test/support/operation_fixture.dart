/// The schema SDL of the operation emitter tests.
const String operationSchema = '''
enum Role { ADMIN }
scalar DateTime
scalar Cursor
interface Node { id: ID! }
type User implements Node {
  id: ID!
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}
type Bot implements Node {
  id: ID!
  model: String
}
union SearchResult = User | Bot
input SearchBy @oneOf {
  name: String
  id: ID
}
input UserFilter {
  role: Role
  ids: [ID!]!
}
type Mutation {
  renameUser(id: ID!, name: String!): User
}
type Subscription {
  userChanged(id: ID!): User
}
type Query {
  user(id: ID!): User
  node(id: ID!): Node
  search(by: SearchBy!, filter: UserFilter, tags: [String!]): [SearchResult!]!
}
''';

/// A valid document: `GetUser`, `UserCard`, `FindNode`, `SearchAll`,
/// `RenameUser`, `UserChanged` and `Everyone`.
const String operationDocument = r'''
query GetUser($id: ID!, $withFriends: Boolean = false, $full: Boolean!) {
  user(id: $id) {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}

fragment UserCard on User {
  id
  name
}

query FindNode($id: ID!) {
  node(id: $id) {
    id
    ... on User {
      name
      ...UserCard
    }
    ... on Bot {
      model
    }
  }
}

query SearchAll($by: SearchBy!, $filter: UserFilter, $tags: [String!]) {
  search(by: $by, filter: $filter, tags: $tags) {
    __typename
  }
}

mutation RenameUser($id: ID!, $name: String!) {
  renameUser(id: $id, name: $name) {
    ...UserCard
  }
}

subscription UserChanged($id: ID!) {
  userChanged(id: $id) {
    id
    name
  }
}

query Everyone {
  node(id: "1") {
    id
  }
}
''';
