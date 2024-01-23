class SourceLocation {
  final int line;
  final int column;
  final String? sourceName;

  SourceLocation(this.line, this.column, [this.sourceName]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceLocation &&
          runtimeType == other.runtimeType &&
          line == other.line &&
          column == other.column &&
          sourceName == other.sourceName;

  @override
  int get hashCode {
    int result = 1;

    result = 31 * result + line.hashCode;
    result = 31 * result + column.hashCode;
    result = 31 * result + (sourceName?.hashCode ?? 0);

    return result;
  }

  @override
  String toString() {
    return 'SourceLocation{line: $line, column: $column, sourceName: $sourceName}';
  }
}
