import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();
  final whitelist = ColumnWhitelist(
    {'name': 'full_name', 'friend': 'friend_id', 'alias': 'full_name'},
    always: ['id'],
  );

  test('gives the sorted columns of the fields the map knows', () async {
    final selection = await f.selection(
      'user',
      '{ user { friend { name } name } }',
    );
    expect(whitelist.columnsFor(selection), ['friend_id', 'full_name', 'id']);
  });

  test('ignores the fields the map does not know', () async {
    final selection = await f.selection('user', '{ user { posts { title } } }');
    expect(whitelist.columnsFor(selection), ['id']);
  });

  test('lists a column once when two fields share it', () async {
    final both = ColumnWhitelist({'name': 'n', 'friend': 'n'});
    final selection = await f.selection(
      'user',
      '{ user { name friend { name } } }',
    );
    expect(both.columnsFor(selection), ['n']);
  });

  test('adds the always columns to an empty selection', () {
    expect(whitelist.columnsFor(FieldSelection.empty), ['id']);
  });

  test('reads names, so an alias does not hide a column', () async {
    final selection = await f.selection('user', '{ user { shown: name } }');
    expect(whitelist.columnsFor(selection), ['full_name', 'id']);
  });
}
