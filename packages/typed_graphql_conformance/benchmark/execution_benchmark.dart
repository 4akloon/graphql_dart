import 'dart:async';
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// One measured operation: a [name] and a [run] that executes it.
typedef BenchmarkScenario = ({
  String name,
  FutureOr<ResponsePayload> Function() run,
});

/// A node of the tree the nested scenario reads.
final class BenchmarkNode {
  const BenchmarkNode(this.id, this.children);

  final int id;
  final List<BenchmarkNode> children;
}

/// The executor benchmark of M5 (spec 14, R4.17); run it by hand, see the
/// package README. Each scenario builds its schema and document once, so a
/// run measures execution only.
final class ExecutionBenchmark {
  const ExecutionBenchmark();

  static const int _rowCount = 1000;
  static const int _fieldCount = 10;
  static const int _treeDepth = 4;
  static const int _treeBreadth = 5;

  /// Every scenario, in the order the benchmark prints them.
  List<BenchmarkScenario> scenarios() => [
    syncRows(),
    asyncRows(),
    nestedFragments(),
    introspection(),
  ];

  /// A query of 1000 objects with 10 synchronous fields each.
  BenchmarkScenario syncRows() => _rows('sync rows', isAsync: false);

  /// The same query with resolvers that return futures.
  BenchmarkScenario asyncRows() => _rows('async rows', isAsync: true);

  /// A tree of 781 nodes read through a fragment at five levels.
  BenchmarkScenario nestedFragments() {
    final b = ExecutableSchemaBuilder<Object?>();
    // Assigned right below; the field list is built on first use, after it.
    late final ObjectTypeDef<BenchmarkNode> node;
    node = b.object<BenchmarkNode>(
      'Node',
      fields: (t) => [
        t.field('id', b.int).pure((value) => value.id),
        t.field('name', b.string).pure((value) => 'node ${value.id}'),
        t.field('children', b.list(node)).pure((value) => value.children),
      ],
    );
    final tree = _tree(_treeDepth);
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('tree', node).pure((_) => tree),
        ],
      ),
    );
    var selection = '...Fields';
    for (var level = 0; level < _treeDepth; level++) {
      selection = '...Fields children { $selection }';
    }
    final text =
        'query { tree { $selection } } '
        'fragment Fields on Node { id name }';
    return _scenario('nested fragments', schema, text);
  }

  /// The full introspection query against a schema of 40 object types.
  BenchmarkScenario introspection() {
    final b = ExecutableSchemaBuilder<Object?>();
    final types = [
      for (var typeIndex = 0; typeIndex < 40; typeIndex++)
        b.object<Object?>(
          'Type$typeIndex',
          description: 'The type number $typeIndex.',
          fields: (t) => [
            for (var index = 0; index < _fieldCount; index++)
              t.field('field$index', b.string.nullable).pure((_) => 'value'),
          ],
        ),
    ];
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          for (var index = 0; index < types.length; index++)
            t.field('type$index', types[index].nullable).pure((_) => null),
        ],
      ),
    );
    return _scenario('introspection', schema, IntrospectionQuery.full.text);
  }

  /// Warms [scenario] up, runs it for [duration] and prints operations per
  /// second and the growth of the resident set.
  Future<void> measure(
    BenchmarkScenario scenario, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    for (var index = 0; index < 20; index++) {
      await scenario.run();
    }
    final rssBefore = ProcessInfo.currentRss;
    final stopwatch = Stopwatch()..start();
    var count = 0;
    while (stopwatch.elapsed < duration) {
      await scenario.run();
      count++;
    }
    final seconds = stopwatch.elapsedMicroseconds / 1000000;
    final growth = (ProcessInfo.currentRss - rssBefore) / (1024 * 1024);
    stdout.writeln(
      '${scenario.name.padRight(18)} '
      '${(count / seconds).toStringAsFixed(1).padLeft(10)} ops/s  '
      'RSS growth ${growth.toStringAsFixed(1)} MiB',
    );
  }

  BenchmarkScenario _rows(String name, {required bool isAsync}) {
    final b = ExecutableSchemaBuilder<Object?>();
    final row = b.object<int>(
      'Row',
      fields: (t) => [
        for (var index = 0; index < _fieldCount; index++)
          if (isAsync)
            t
                .field('field$index', b.int)
                .resolve(
                  (value, args, context, info) => Future.value(value + index),
                )
          else
            t.field('field$index', b.int).pure((value) => value + index),
      ],
    );
    final rows = List<int>.generate(_rowCount, (index) => index);
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('rows', b.list(row)).pure((_) => rows),
        ],
      ),
    );
    final selection = [
      for (var index = 0; index < _fieldCount; index++) 'field$index',
    ].join(' ');
    return _scenario(name, schema, '{ rows { $selection } }');
  }

  BenchmarkScenario _scenario(
    String name,
    ExecutableSchema<Object?> schema,
    String text,
  ) {
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    );
    return (name: name, run: () => schema.execute(document, context: null));
  }

  BenchmarkNode _tree(int remaining) {
    // Ids need not be unique: the benchmark reads values, it never compares.
    return BenchmarkNode(remaining, [
      if (remaining > 0)
        for (var index = 0; index < _treeBreadth; index++) _tree(remaining - 1),
    ]);
  }
}

Future<void> main() async {
  stdout.writeln('Dart ${Platform.version.split(' ').first}');
  const benchmark = ExecutionBenchmark();
  for (final scenario in benchmark.scenarios()) {
    await benchmark.measure(scenario);
  }
}
