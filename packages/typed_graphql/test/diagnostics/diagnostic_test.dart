import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('DiagnosticCode', () {
    test('every id is GQL and three digits', () {
      for (final code in DiagnosticCode.values) {
        expect(code.id, matches(RegExp(r'^GQL[0-5]\d\d$')), reason: code.name);
      }
    });

    test('Suggestions is reachable from the barrel', () {
      expect(const Suggestions().didYouMean(['a']), ' Did you mean "a"?');
    });

    test('ids are unique and sorted', () {
      final ids = [for (final code in DiagnosticCode.values) code.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, [...ids]..sort());
    });

    test('names the multipart upload codes', () {
      expect(DiagnosticCode.malformedMultipartRequest.id, 'GQL440');
      expect(DiagnosticCode.uploadTooLarge.id, 'GQL441');
      expect(DiagnosticCode.tooManyUploads.id, 'GQL442');
    });

    test('keeps the ids already published', () {
      expect(DiagnosticCode.diagnosticLimitReached.id, 'GQL000');
    });
  });

  group('Diagnostic', () {
    final source = Source('{\n  a\n  b\n}', name: 'q.graphql');

    test('prints the place, the severity, the id and the message', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Too many errors.',
        span: SourceSpan(source, 4, 5),
      );
      expect(
        diagnostic.toString(),
        'q.graphql:2:3: error GQL000: Too many errors.',
      );
    });

    test('prints without a place when it has no span', () {
      final diagnostic = Diagnostic(.diagnosticLimitReached, .warning, 'Hm.');
      expect(diagnostic.toString(), 'warning GQL000: Hm.');
    });

    test('isError follows the severity', () {
      expect(Diagnostic(.diagnosticLimitReached, .error, 'x').isError, isTrue);
      expect(
        Diagnostic(.diagnosticLimitReached, .warning, 'x').isError,
        isFalse,
      );
    });

    test('lists the location of the span, then of the related spans', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Fields conflict.',
        span: SourceSpan(source, 4, 5),
        related: [SourceSpan(source, 8, 9)],
      );
      expect(diagnostic.locations, const [
        SourceLocation(2, 3),
        SourceLocation(3, 3),
      ]);
    });

    test('has no locations without spans', () {
      expect(
        Diagnostic(.diagnosticLimitReached, .error, 'x').locations,
        isEmpty,
      );
    });

    test('copies the related spans', () {
      final related = [SourceSpan(source, 8, 9)];
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'x',
        related: related,
      );
      related.clear();
      expect(diagnostic.related, hasLength(1));
      expect(
        () => diagnostic.related.add(SourceSpan(source, 0, 1)),
        throwsUnsupportedError,
      );
    });

    group('equality', () {
      Diagnostic make({
        String message = 'x',
        int end = 5,
        List<SourceSpan> related = const [],
      }) => Diagnostic(
        .diagnosticLimitReached,
        .error,
        message,
        span: SourceSpan(source, 4, end),
        related: related,
      );

      test('equal fields make equal diagnostics with equal hash codes', () {
        final related = [SourceSpan(source, 8, 9)];
        expect(make(related: related), make(related: [...related]));
        expect(
          make(related: related).hashCode,
          make(related: [...related]).hashCode,
        );
      });

      test('a different message, span or related list differs', () {
        expect(make(message: 'y'), isNot(make()));
        expect(make(end: 6), isNot(make()));
        expect(make(related: [SourceSpan(source, 8, 9)]), isNot(make()));
      });

      test('a different severity differs', () {
        expect(
          Diagnostic(.diagnosticLimitReached, .warning, 'x'),
          isNot(Diagnostic(.diagnosticLimitReached, .error, 'x')),
        );
      });
    });
  });
}
