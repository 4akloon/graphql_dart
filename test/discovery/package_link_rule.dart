/// The rule that a link in a package README stays inside the package folder,
/// because pub.dev publishes that folder alone.
final class const PackageLinkRule(
  /// The package folder with its trailing slash, e.g. `packages/a/`.
  final String folder,
) {
  /// Creates the rule for [folder].
  this;

  /// Whether [target], written in the file at [from], resolves to a path
  /// inside the package folder.
  bool allows(String from, String target) =>
      Uri.parse(from).resolve(target).path.startsWith(folder);
}
