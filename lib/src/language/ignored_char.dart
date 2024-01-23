import 'source_location.dart';

enum IgnoredCharKind { space, comma, tab, cr, lf, other }

class IgnoredChar {
  final String value;
  final IgnoredCharKind kind;
  final SourceLocation sourceLocation;

  IgnoredChar(this.value, this.kind, this.sourceLocation);

  @override
  String toString() {
    return 'IgnoredChar(value: $value, kind: $kind, sourceLocation: $sourceLocation)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IgnoredChar &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          kind == other.kind &&
          sourceLocation == other.sourceLocation;

  @override
  int get hashCode {
    int result = 1;

    result = 31 * result + value.hashCode;
    result = 31 * result + kind.hashCode;
    result = 31 * result + sourceLocation.hashCode;

    return result;
  }
}
