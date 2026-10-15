/// A map key made of parts compared by identity (syntax nodes) or by value
/// (type names), so two plans over the very same field nodes meet in a set
/// without printing or hashing the nodes' contents.
final class IdentityKey {
  /// Creates the key of [parts]: strings compare by value, anything else by
  /// identity.
  IdentityKey(this._parts)
    : hashCode = Object.hashAll([
        for (final part in _parts)
          if (part is String) part.hashCode else identityHashCode(part),
      ]);

  final List<Object> _parts;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! IdentityKey || other._parts.length != _parts.length) {
      return false;
    }
    for (var i = 0; i < _parts.length; i++) {
      final mine = _parts[i];
      final theirs = other._parts[i];
      if (mine is String ? mine != theirs : !identical(mine, theirs)) {
        return false;
      }
    }
    return true;
  }
}
