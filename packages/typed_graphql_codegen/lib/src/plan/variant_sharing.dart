import 'collected_selection.dart';
import 'condition.dart';
import 'field_group.dart';
import 'fragment_use.dart';

/// Decides what the sealed base of a polymorphic selection declares: a base
/// field or fragment holder is shared when every variant selects exactly
/// what the base does (spec §6, "Variants").
final class VariantSharing {
  /// Compares [base] with the collection of each of [variants].
  VariantSharing(CollectedSelection base, List<CollectedSelection> variants)
    : sharedFields = _sharedFields(base, variants),
      hasSharedHolder =
          base.fragments.isNotEmpty &&
          variants.every((v) => _sameFragments(base.fragments, v.fragments));

  /// The response names of the shared base fields.
  final Set<String> sharedFields;

  /// Whether the base declares the fragment holder.
  final bool hasSharedHolder;

  static Set<String> _sharedFields(
    CollectedSelection base,
    List<CollectedSelection> variants,
  ) {
    final byVariant = [
      for (final variant in variants)
        {for (final group in variant.fields) group.responseName: group},
    ];
    return {
      for (final group in base.fields)
        if (byVariant.every(
          (groups) => _sameNodes(group, groups[group.responseName]),
        ))
          group.responseName,
    };
  }

  static bool _sameNodes(FieldGroup base, FieldGroup? other) {
    if (other == null || other.nodes.length != base.nodes.length) {
      return false;
    }
    for (var index = 0; index < base.nodes.length; index++) {
      if (!identical(base.nodes[index], other.nodes[index])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameFragments(List<FragmentUse> base, List<FragmentUse> other) {
    if (base.length != other.length) {
      return false;
    }
    for (var index = 0; index < base.length; index++) {
      final left = base[index];
      final right = other[index];
      if (left.fragmentName != right.fragmentName ||
          !_sameAlternatives(left.whenAny, right.whenAny)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameAlternatives(
    List<List<Condition>> a,
    List<List<Condition>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index].length != b[index].length) {
        return false;
      }
      for (var inner = 0; inner < a[index].length; inner++) {
        if (a[index][inner] != b[index][inner]) {
          return false;
        }
      }
    }
    return true;
  }
}
