import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'condition.dart';
import 'fragment_use.dart';

/// A fragment a data class spreads, as a member of its holder.
final class PlannedFragment {
  /// Plans [use].
  PlannedFragment(FragmentUse use)
    : fragmentName = use.fragmentName,
      className = const DartNames().typeName(use.fragmentName),
      memberName = const DartNames().memberName(
        use.fragmentName,
        reservedMembers: DartNames.objectMembers,
      ),
      spread = use.spread,
      whenAny = use.whenAny,
      isConditional = use.isConditional;

  /// The fragment's name.
  final String fragmentName;

  /// The class generated for the fragment.
  final String className;

  /// The holder member the fragment is read through.
  final String memberName;

  /// The first spread node of the fragment.
  final FragmentSpread? spread;

  /// The spread is selected when all conditions of any one list hold.
  final List<List<Condition>> whenAny;

  /// Whether the fragment may be absent.
  final bool isConditional;
}
