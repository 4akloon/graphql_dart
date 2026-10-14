@TestOn('vm')
library;

import 'package:test/test.dart';

import 'readme_outline.dart';

void main() {
  const readme =
      '# name\n'
      '\n'
      '![Dart](https://img.shields.io/a)\n'
      '[![CI](https://x.dev/b.svg)](https://x.dev/c)\n'
      '\n'
      '**Parse GraphQL\n'
      'in Dart.** More.\n'
      '\n'
      '> **Status: skeleton.** Later.\n'
      '\n'
      '## Install\n'
      '\n'
      '```sh\n'
      '## not a heading\n'
      '```\n'
      '\n'
      '## Usage\n'
      '\n'
      'Text.\n';

  test('the opening paragraphs leave out the title and the badges', () {
    expect(ReadmeOutline(readme).opening, [
      '**Parse GraphQL in Dart.** More.',
      '> **Status: skeleton.** Later.',
    ]);
  });

  test('reads the status from the banner', () {
    expect(ReadmeOutline(readme).status, 'skeleton');
  });

  test('a README without a banner has no status', () {
    expect(ReadmeOutline('# name\n\nText.\n').status, isNull);
  });

  test('a fenced line that looks like a heading is not one', () {
    expect(ReadmeOutline(readme).headings, ['Install', 'Usage']);
  });

  test('a section runs up to the next heading', () {
    expect(ReadmeOutline(readme).section('Usage'), 'Text.');
  });

  test('a missing section is empty', () {
    expect(ReadmeOutline(readme).section('License'), isEmpty);
  });

  test('reads a README written with CRLF line endings', () {
    final windows = ReadmeOutline(readme.replaceAll('\n', '\r\n'));
    expect(windows.headings, ['Install', 'Usage']);
  });
}
