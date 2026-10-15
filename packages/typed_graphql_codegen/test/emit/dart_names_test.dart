import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_names.dart';

void main() {
  const DartNames names = DartNames();

  final Map<String, String> types = <String, String>{
    'user': 'User',
    'User': 'User',
    'UUID': 'UUID',
    'USER_ROLE': 'UserRole',
    'user_role': 'UserRole',
    '__Schema': r'$$Schema',
    '_foo_bar': r'$FooBar',
    'A_B': 'AB',
    'Get_user': 'GetUser',
  };
  types.forEach((name, dart) {
    test('typeName of $name', () => expect(names.typeName(name), dart));
  });

  final Map<String, String> members = <String, String>{
    '__typename': 'typename',
    'ID': 'id',
    'ADMIN': 'admin',
    'UserName': 'userName',
    'createdAt': 'createdAt',
    'NOT_FOUND': 'notFound',
    'user_name': 'userName',
    'user_ID': 'userId',
    '_id': r'$id',
    '__x': r'$$x',
    'default': r'default$',
    'class': r'class$',
    'in': r'in$',
  };
  members.forEach((name, dart) {
    test('memberName of $name', () => expect(names.memberName(name), dart));
  });

  test('memberName escapes a reserved member', () {
    expect(
      names.memberName('toJson', reservedMembers: DartNames.objectMembers),
      r'toJson$',
    );
  });

  test('memberName escapes the import prefixes of the generated code', () {
    expect(
      [
        for (final name in ['client', 'graphql'])
          names.memberName(name, reservedMembers: DartNames.objectMembers),
      ],
      [r'client$', r'graphql$'],
    );
  });

  test('memberName leaves a member the caller did not reserve', () {
    expect(names.memberName('toJson'), 'toJson');
  });

  test('enum members include the members of Enum', () {
    expect(
      <bool>[
        for (final String name in <String>['values', 'index', 'name'])
          DartNames.enumMembers.contains(name),
      ],
      <bool>[true, true, true],
    );
  });

  test('capitalized upper-cases the first character', () {
    expect(
      <String>[
        names.capitalized('userName'),
        names.capitalized(r'$id'),
        names.capitalized(r'default$'),
      ],
      <String>['UserName', r'$id', r'Default$'],
    );
  });
}
