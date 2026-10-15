import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/field_lane.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class User {
  const User(this.name);
  final String name;
}

final class Admin extends User {
  const Admin(super.name);
}

final class AppContext {
  const AppContext(this.greeting);
  final String greeting;
}

void main() {
  FieldInfo infoOf(String field) => FieldInfo(
    fieldName: field,
    parentTypeName: 'User',
    path: [PathKey(field)],
  );

  final b = ExecutableSchemaBuilder<AppContext>();
  final times = Arg('times', b.int, defaultValue: 1);

  FieldDef<User, AppContext> fieldOf(
    FieldDef<User, AppContext> Function(FieldsBuilder<User, AppContext> t) make,
  ) => make(FieldsBuilder<User, AppContext>());

  group('fields', () {
    test('pure reads the parent through the pure lane', () {
      final field = fieldOf(
        (t) => t.field('name', b.string).pure((user) => user.name),
      );
      final lane = field.lane as PureLane;
      expect(lane.read(const User('Ada')), 'Ada');
    });

    test('pure casts the parent to P', () {
      final field = fieldOf(
        (t) => t.field('name', b.string).pure((user) => user.name),
      );
      final lane = field.lane as PureLane;
      expect(() => lane.read('not a user'), throwsA(isA<TypeError>()));
    });

    test('resolve passes the parent, arguments, context and info', () {
      final field = fieldOf(
        (t) => t
            .field('shout', b.string, args: [times])
            .resolve(
              (user, args, ctx, info) =>
                  '${ctx.greeting} ${user.name} ${args.get(times)} '
                  '${info.fieldName}',
            ),
      );
      final lane = field.lane as ResolverLane;
      final result = lane.resolve(
        const User('Ada'),
        Arguments(field.args, {'times': 2}),
        const AppContext('hi'),
        infoOf('shout'),
      );
      expect(result, 'hi Ada 2 shout');
    });

    test('resolveWith decodes the arguments class', () {
      final field = fieldOf(
        (t) => t
            .field('repeat', b.string)
            .resolveWith<int>(
              ArgumentsDef([times], (arguments) => arguments.get(times) * 10),
              (user, count, ctx, info) => '${user.name}$count',
            ),
      );
      final lane = field.lane as ResolverLane;
      final result = lane.resolve(
        const User('Ada'),
        Arguments(field.args, {'times': 3}),
        const AppContext('hi'),
        infoOf('repeat'),
      );
      expect(result, 'Ada30');
      expect(field.args, hasLength(1));
    });

    test('args together with resolveWith is an ArgumentError', () {
      expect(
        () => fieldOf(
          (t) => t
              .field('repeat', b.string, args: [times])
              .resolveWith<int>(
                ArgumentsDef([times], (arguments) => 1),
                (user, count, ctx, info) => '',
              ),
        ),
        throwsArgumentError,
      );
    });

    test('declareOnly has the declared-only lane', () {
      final field = fieldOf((t) => t.field('name', b.string).declareOnly());
      expect(field.lane, isA<DeclaredOnlyLane>());
    });

    test('modifiers keep the other settings', () {
      final directive = AppliedDirective('tag');
      final field = fieldOf(
        (t) => t
            .field('name', b.string, description: 'The name.')
            .deprecated('Use nick.')
            .withDirectives([directive])
            .pure((user) => user.name),
      );
      expect(field.description, 'The name.');
      expect(field.deprecationReason, 'Use nick.');
      expect(field.directives, [directive]);
    });
  });

  group('object types', () {
    test('accepts a value of the Dart type or a subtype', () {
      final user = b.object<User>('User', fields: (t) => []);
      expect(user.accepts(const Admin('Ada')), isTrue);
      expect(user.accepts('text'), isFalse);
    });

    test('isTypeOf replaces the Dart type test', () {
      final admin = b.object<User>(
        'Admin',
        fields: (t) => [],
        options: ObjectOptions(isTypeOf: (value) => value is Admin),
      );
      expect(admin.accepts(const User('Ada')), isFalse);
      expect(admin.accepts(const Admin('Ada')), isTrue);
    });

    test('fields run once, on first read', () {
      var calls = 0;
      final user = b.object<User>(
        'Counted',
        fields: (t) {
          calls++;
          return [t.field('name', b.string).pure((u) => u.name)];
        },
      );
      expect(calls, 0);
      expect(user.fields.map((field) => field.name), ['name']);
      expect(user.fields, hasLength(1));
      expect(calls, 1);
    });

    test('the builder records the object', () {
      final fresh = ExecutableSchemaBuilder<AppContext>();
      final user = fresh.object<User>('User', fields: (t) => []);
      expect(fresh.definitions, [user]);
    });

    test('typeRef prints as a non-null named type', () {
      final user = b.object<User>('User', fields: (t) => []);
      expect(const Printer().print(user.typeRef), 'User!');
      expect(const Printer().print(user.nullable.typeRef), 'User');
    });
  });
}
