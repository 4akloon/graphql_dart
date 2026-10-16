import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('ServerProfile.development', () {
    const profile = ServerProfile.development;

    test('enables introspection', () {
      expect(profile.introspection, IntrospectionPolicy.enabled);
    });

    test('includes suggestions', () {
      expect(profile.includesSuggestions, true);
    });

    test('does not mask errors', () => expect(profile.maskErrors, false));

    test('prevents CSRF', () {
      expect(profile.csrfPrevention, const CsrfPrevention());
    });

    test('uses the development limits', () {
      expect(profile.limits, ServerLimits.development);
    });

    test('has no timeout', () => expect(profile.timeout, isNull));

    test('serves GraphiQL', () => expect(profile.graphiql, true));
  });

  group('ServerProfile.production', () {
    const profile = ServerProfile.production;

    test('disables introspection', () {
      expect(profile.introspection, IntrospectionPolicy.disabled);
    });

    test('omits suggestions', () {
      expect(profile.includesSuggestions, false);
    });

    test('masks errors', () => expect(profile.maskErrors, true));

    test('prevents CSRF', () {
      expect(profile.csrfPrevention, const CsrfPrevention());
    });

    test('uses the production limits', () {
      expect(profile.limits, ServerLimits.production);
    });

    test('has no timeout', () => expect(profile.timeout, isNull));

    test('does not serve GraphiQL', () => expect(profile.graphiql, false));
  });

  group('ServerProfile with methods', () {
    const base = ServerProfile.production;

    test('withIntrospection changes only the introspection', () {
      final copy = base.withIntrospection(IntrospectionPolicy.enabled);
      expect(copy.introspection, IntrospectionPolicy.enabled);
      expect(copy.withIntrospection(IntrospectionPolicy.disabled), base);
    });

    test('withSuggestions changes only the suggestions', () {
      final copy = base.withSuggestions(true);
      expect(copy.includesSuggestions, true);
      expect(copy.withSuggestions(false), base);
    });

    test('withErrorMasking changes only the masking', () {
      final copy = base.withErrorMasking(false);
      expect(copy.maskErrors, false);
      expect(copy.withErrorMasking(true), base);
    });

    test('withCsrfPrevention accepts null to turn the rule off', () {
      final copy = base.withCsrfPrevention(null);
      expect(copy.csrfPrevention, isNull);
      expect(copy.withCsrfPrevention(const CsrfPrevention()), base);
    });

    test('withLimits changes only the limits', () {
      final copy = base.withLimits(ServerLimits.development);
      expect(copy.limits, ServerLimits.development);
      expect(copy.withLimits(ServerLimits.production), base);
    });

    test('withTimeout changes only the timeout', () {
      final copy = base.withTimeout(const Duration(seconds: 5));
      expect(copy.timeout, const Duration(seconds: 5));
      expect(copy.withTimeout(null), base);
    });

    test('withGraphiQL changes only the GraphiQL switch', () {
      final copy = base.withGraphiQL(true);
      expect(copy.graphiql, true);
      expect(copy.withGraphiQL(false), base);
    });
  });

  group('ServerProfile with methods keep the other fields', () {
    final base = ServerProfile.production
        .withCsrfPrevention(null)
        .withTimeout(const Duration(seconds: 5))
        .withGraphiQL(true);

    void expectKept(ServerProfile copy) {
      expect(copy.timeout, const Duration(seconds: 5));
      expect(copy.csrfPrevention, isNull);
      expect(copy.graphiql, true);
    }

    test('withCsrfPrevention', () {
      expectKept(
        base
            .withCsrfPrevention(const CsrfPrevention())
            .withCsrfPrevention(null),
      );
    });

    test(
      'withTimeout',
      () => expectKept(base.withTimeout(const Duration(seconds: 5))),
    );

    test('withIntrospection', () {
      expectKept(base.withIntrospection(IntrospectionPolicy.enabled));
    });

    test('withSuggestions', () => expectKept(base.withSuggestions(true)));

    test('withErrorMasking', () => expectKept(base.withErrorMasking(false)));

    test(
      'withLimits',
      () => expectKept(base.withLimits(ServerLimits.development)),
    );
  });

  group('ServerProfile equality', () {
    test('equal profiles have equal hash codes', () {
      // Built at run time, so it is not the canonical constant.
      final copy = ServerProfile(
        introspection: IntrospectionPolicy.values.byName('disabled'),
        includesSuggestions: false,
        maskErrors: true,
        csrfPrevention: const CsrfPrevention(),
        limits: ServerLimits.production,
      );
      expect(copy, ServerProfile.production);
      expect(copy.hashCode, ServerProfile.production.hashCode);
    });

    test('differ when only GraphiQL differs', () {
      final other = ServerProfile.production.withGraphiQL(true);
      expect(other, isNot(ServerProfile.production));
      expect(other.hashCode, isNot(ServerProfile.production.hashCode));
    });

    test('the two constants differ', () {
      expect(ServerProfile.development, isNot(ServerProfile.production));
    });
  });

  group('ServerLimits', () {
    List<Object?> fieldsOf(ServerLimits limits) => [
      limits.maxDocumentLength,
      limits.maxTokens,
      limits.maxDepth,
      limits.maxAliases,
      limits.maxDirectives,
      limits.maxCost,
      limits.defaultListSize,
    ];

    test('development bounds the text only', () {
      expect(fieldsOf(ServerLimits.development), [
        100000,
        15000,
        null,
        null,
        null,
        null,
        10,
      ]);
    });

    test('production sets every limit', () {
      expect(fieldsOf(ServerLimits.production), [
        100000,
        15000,
        15,
        15,
        50,
        10000.0,
        10,
      ]);
    });

    test('compare by value', () {
      expect(const ServerLimits(maxDepth: 3), const ServerLimits(maxDepth: 3));
      expect(
        const ServerLimits(maxDepth: 3).hashCode,
        const ServerLimits(maxDepth: 3).hashCode,
      );
    });

    test('a NaN cost is a programmer error', () {
      expect(
        () => ServerLimits(maxCost: double.nan),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a negative depth is a programmer error', () {
      expect(() => ServerLimits(maxDepth: -1), throwsA(isA<AssertionError>()));
    });

    test('a negative default list size is a programmer error', () {
      expect(
        () => ServerLimits(defaultListSize: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('differ when one limit differs', () {
      expect(
        const ServerLimits(maxCost: 1),
        isNot(const ServerLimits(maxCost: 2)),
      );
    });
  });
}
