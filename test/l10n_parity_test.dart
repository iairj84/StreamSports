import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Translation dictionaries are keyed by the English text in the code, so a
/// renamed English string silently orphans its translations (the UI falls
/// back to English) and a mistyped `{placeholder}` drops a value. These
/// tests parse lib/l10n/{fr,es,it}.dart and the lib/ sources to catch both,
/// plus a ratchet on strings that are still English-only: adding a new
/// user-visible string without translating it fails until it is either
/// translated in all three dictionaries or recorded in
/// test/fixtures/l10n_untranslated.txt.
//
// Refreshing the fixture after translating strings:
//   delete the translated lines from test/fixtures/l10n_untranslated.txt
//   (one per line, `\n` for a newline inside a string) and rerun.
// Only single-line, single-quoted tr('...') / tr("...") literals are
// tracked; multiline, concatenated and computed keys are skipped by the
// source scan but still covered against renames by the orphan check below.

final _keyPattern = RegExp(r"^(\s*)'((?:[^'\\\n]|\\.)*)':", multiLine: true);
final _placeholderPattern = RegExp(r'\{(\w+)\}');

String _unescapeDart(String s) {
  final out = StringBuffer();
  var i = 0;
  const simple = {
    'n': '\n',
    'r': '\r',
    't': '\t',
    'b': '\b',
    'f': '\f',
    'v': '\v',
    "'": "'",
    '"': '"',
    r'$': r'$',
    r'\': r'\',
  };
  while (i < s.length) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final next = s[i + 1];
      final mapped = simple[next];
      if (mapped != null) {
        out.write(mapped);
        i += 2;
        continue;
      }
      if (next == 'u' && i + 6 <= s.length) {
        final code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
        if (code != null) {
          out.write(String.fromCharCode(code));
          i += 6;
          continue;
        }
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

String _singleQuoted(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');

String _doubleQuoted(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t')
    .replaceAll('"', r'\"')
    .replaceAll(r'$', r'\$');

/// Entries parsed from one dictionary file: the runtime key and value.
List<(String, String)> _dictionary(String lang) {
  final src = File('lib/l10n/$lang.dart').readAsStringSync();
  final entries = <(String, String)>[];
  for (final m in _keyPattern.allMatches(src)) {
    var i = m.end;
    while (i < src.length && ' \t\r\n'.contains(src[i])) {
      i++;
    }
    final quote = src[i];
    i++;
    final value = StringBuffer();
    while (i < src.length) {
      final c = src[i];
      if (c == r'\' && i + 1 < src.length) {
        value.write(src.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (c == quote) break;
      value.write(c);
      i++;
    }
    entries.add((_unescapeDart(m.group(2)!), _unescapeDart(value.toString())));
  }
  return entries;
}

String _libText() {
  final out = StringBuffer();
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      out.writeln(f.readAsStringSync());
    }
  }
  return out.toString();
}

final _trSingle = RegExp(r"\btr\(\s*'((?:[^'\\\n]|\\.)*)'");
final _trDouble = RegExp(r'\btr\(\s*"((?:[^"\\\n]|\\.)*)"');

void main() {
  late Map<String, List<(String, String)>> dicts;
  late String lib;
  late Set<String> staticKeys;

  setUpAll(() {
    dicts = {
      for (final lang in ['fr', 'es', 'it']) lang: _dictionary(lang),
    };
    lib = _libText();
    staticKeys = {
      for (final pattern in [_trSingle, _trDouble])
        for (final m in pattern.allMatches(lib))
          _unescapeDart(m.group(1)!),
    };
  });

  test('placeholders match between keys and translations', () {
    // {s} is an English-style plural filled by the code; other languages
    // phrase around it, so only it may be dropped.
    final offenders = <String>[];
    for (final entry in dicts.entries) {
      for (final (key, value) in entry.value) {
        final expected =
            _placeholderPattern.allMatches(key).map((m) => m.group(1)!).toSet()
              ..remove('s');
        final actual = _placeholderPattern
            .allMatches(value)
            .map((m) => m.group(1)!)
            .toSet()
          ..remove('s');
        if (expected.length != actual.length ||
            !expected.containsAll(actual)) {
          offenders.add('${entry.key}: ${key.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Fix the {placeholders} in:\n${offenders.join('\n')}');
  });

  test('no translation key is orphaned by a rename', () {
    final orphans = <String>[];
    for (final entry in dicts.entries) {
      for (final (key, _) in entry.value) {
        if (!lib.contains("'${_singleQuoted(key)}'") &&
            !lib.contains('"${_doubleQuoted(key)}"')) {
          orphans.add('${entry.key}: ${key.trim()}');
        }
      }
    }
    expect(orphans, isEmpty,
        reason: 'These keys appear in no lib/ source; the English text was '
            'renamed or removed, so update or drop them:\n'
            '${orphans.join('\n')}');
  });

  test('new user-visible strings are translated or recorded', () {
    final translated = <String>{
      for (final entries in dicts.values)
        for (final (key, _) in entries) key,
    };
    final missing = staticKeys.where((k) => !translated.contains(k)).toSet();
    final recorded = File('test/fixtures/l10n_untranslated.txt')
        .readAsLinesSync()
        .map((line) => line.replaceAll(r'\n', '\n'))
        .toSet();
    final unexpected =
        missing.where((k) => !recorded.contains(k)).toList()..sort();
    final stale =
        recorded.where((k) => !missing.contains(k)).toList()..sort();
    expect(unexpected, isEmpty,
        reason: 'Translate these in fr/es/it, or record them in '
            'test/fixtures/l10n_untranslated.txt:\n'
            '${unexpected.join('\n')}');
    expect(stale, isEmpty,
        reason: 'These are translated now; remove them from '
            'test/fixtures/l10n_untranslated.txt:\n'
            '${stale.join('\n')}');
  });
}
