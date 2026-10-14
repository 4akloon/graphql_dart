/// A CSV text with a header row, read as RFC 4180: a quoted field may
/// hold commas, line breaks and doubled quotes; `\r\n` ends a record too.
final class CsvTable {
  /// Reads [text]; the first record is the header.
  factory CsvTable.parse(String text) {
    final records = _records(text);
    if (records.isEmpty) {
      throw const FormatException('A CSV table needs a header row.');
    }
    final [header, ...body] = records;
    return CsvTable._(header, [
      for (final record in body)
        {
          for (var i = 0; i < header.length; i++)
            header[i]: i < record.length ? record[i] : '',
        },
    ]);
  }

  CsvTable._(this.header, this.rows);

  /// The column names.
  final List<String> header;

  /// Every record after the header, by column name.
  final List<Map<String, String>> rows;

  static List<List<String>> _records(String text) {
    final records = <List<String>>[];
    var record = <String>[];
    final field = StringBuffer();
    var isQuoted = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (isQuoted) {
        if (char != '"') {
          field.write(char);
        } else if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          isQuoted = false;
        }
        continue;
      }
      if (char == '\r') {
        continue;
      }
      switch (char) {
        case '"':
          isQuoted = true;
        case ',':
          record.add('$field');
          field.clear();
        case '\n':
          record.add('$field');
          field.clear();
          records.add(record);
          record = <String>[];
        default:
          field.write(char);
      }
    }
    if (field.isNotEmpty || record.isNotEmpty) {
      record.add('$field');
      records.add(record);
    }
    return records;
  }
}
