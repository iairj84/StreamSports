import '../models/channel.dart';
import 'channel_names.dart';

/// Optional passes over a provider's channel names, applied as rename
/// overrides so the playlist itself is never edited.
enum ChannelCleanupRule { region, category, quality, numbering, separators }

extension ChannelCleanupRuleLabel on ChannelCleanupRule {
  String get label => switch (this) {
        ChannelCleanupRule.region => 'Region tags',
        ChannelCleanupRule.category => 'Type labels',
        ChannelCleanupRule.quality => 'Quality markers',
        ChannelCleanupRule.numbering => 'Channel numbers',
        ChannelCleanupRule.separators => 'Leftover separators',
      };

  String get description => switch (this) {
        ChannelCleanupRule.region =>
          'US:, [UK], | CA and similar labels at either end of the name',
        ChannelCleanupRule.category =>
          'MOVIE, NEWS, SPT, SPORTS and similar labels between separators',
        ChannelCleanupRule.quality =>
          'HD, FHD, 4K, HEVC, 1080p and other stream markers',
        ChannelCleanupRule.numbering =>
          'Leading numbers such as "001 | " or "23. "',
        ChannelCleanupRule.separators =>
          'Pipes, dashes and spacing a removed label leaves behind',
      };
}

/// One channel the current rules would rename, and what it would become.
typedef ChannelCleanupRow = ({Channel channel, String before, String after});

/// What the preview shows and what an apply writes.
class ChannelCleanupPlan {
  const ChannelCleanupPlan({
    required this.rows,
    required this.skippedRenamed,
    required this.examined,
  });

  final List<ChannelCleanupRow> rows;

  /// Channels left alone because the viewer already named them by hand.
  final int skippedRenamed;

  /// How many channels the rules looked at, for the "N of M" line.
  final int examined;

  bool get isEmpty => rows.isEmpty;
}

/// The rules behind Settings > Channel names > Clean up names.
///
/// Providers pad names with region tags, programme-type labels, quality
/// markers and slot numbers ("US | NEWS | 001 | ESPN HD"), and the same text
/// also feeds Sports matching, so cleaning it up helps the guide read better
/// and the matcher line up. No list of labels is ever complete, so the viewer
/// can add their own words beside the built-in rules.
class ChannelNameCleanup {
  const ChannelNameCleanup._();

  static const Set<ChannelCleanupRule> defaults = {
    ChannelCleanupRule.region,
    ChannelCleanupRule.category,
    ChannelCleanupRule.quality,
    ChannelCleanupRule.numbering,
    ChannelCleanupRule.separators,
  };

  /// Programme-type words providers hang off a channel name. They are only
  /// removed where a separator or the end of the name marks them as a label,
  /// so "Fox News" and "Sky Sports" keep their brand.
  static const List<String> categoryWords = [
    'movie',
    'movies',
    'news',
    'spt',
    'sport',
    'sports',
    'vod',
    'series',
    'kids',
    'ppv',
    'doc',
    'docs',
    'music',
    'entertainment',
  ];

  static List<String> parseWords(String text) => {
        for (final part in text.split(','))
          if (part.trim().length >= 2) part.trim().toLowerCase()
      }.take(50).toList();

  /// Builds the preview. Channels the viewer named by hand are counted and
  /// left alone: a rule must never overwrite a deliberate rename.
  static ChannelCleanupPlan plan(
      Iterable<Channel> channels, Set<ChannelCleanupRule> rules,
      {List<String> words = const []}) {
    final rows = <ChannelCleanupRow>[];
    var skipped = 0;
    var examined = 0;
    for (final channel in channels) {
      examined++;
      if (ChannelRenames.isRenamed(channel)) {
        skipped++;
        continue;
      }
      final after = clean(channel.name, rules, words: words);
      if (after.isEmpty || after == channel.name) continue;
      rows.add((channel: channel, before: channel.name, after: after));
    }
    return ChannelCleanupPlan(
        rows: rows, skippedRenamed: skipped, examined: examined);
  }

  /// Runs the selected rules over one name. Returns the name unchanged when
  /// nothing applies, and never an empty string unless the name was only tags.
  static String clean(String name, Set<ChannelCleanupRule> rules,
      {List<String> words = const []}) {
    if (rules.isEmpty && words.isEmpty) return name;
    var value = name;
    // A name can be padded at both ends ("001 | US: ESPN"), so the passes that
    // work from the edges repeat until they stop finding something.
    for (var pass = 0; pass < 3; pass++) {
      final before = value;
      if (rules.contains(ChannelCleanupRule.numbering)) {
        value = value.replaceFirst(_numbering, '');
      }
      if (rules.contains(ChannelCleanupRule.region)) {
        value = value.replaceFirst(_leadingRegion, '');
        value = value.replaceFirst(_trailingRegion, '');
      }
      if (rules.contains(ChannelCleanupRule.category)) {
        value = value.replaceAll(_categoryLabel, ' ');
      }
      if (value == before) break;
    }
    if (rules.contains(ChannelCleanupRule.quality)) {
      value = value.replaceAll(_quality, ' ');
    }
    if (words.isNotEmpty) {
      for (final word in words) {
        final parts = word
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .map(RegExp.escape)
            .join(r'\s+');
        if (parts.isEmpty) continue;
        // Whole words only, so a custom "SPT" cannot eat "SPORTS".
        value = value.replaceAll(
            RegExp('(?<![a-z0-9])$parts(?![a-z0-9])', caseSensitive: false),
            ' ');
      }
    }
    if (rules.contains(ChannelCleanupRule.separators)) {
      value = value
          .replaceAll(_repeatedSeparators, ' | ')
          .replaceAll(_paddedSeparator, ' | ');
    }
    // Whatever removed something leaves its separator behind; trim the ends
    // and collapse the spaces in every case, rule or not.
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(_edgeSeparators, '')
        .trim();
  }

  static const String _regionCodes =
      'us|usa|uk|gb|ca|can|au|aus|nz|ie|de|fr|es|it|pt|br|mx|ar|cl|co|se|no|dk|fi|nl|be|ch|at|pl|ru|tr|gr|ro|hu|cz|sk|hr|rs|bg|ua|il|sa|ae|za|ph|my|sg|hk|tw|jp|kr|cn|th|vn|id|in|pk|latino|latam';

  /// A country label the provider puts in front: `US:`, `[UK]`, `| CA |`.
  static final _leadingRegion = RegExp(
      '^\\s*(?:\\[\\s*(?:$_regionCodes)\\s*\\]|\\(\\s*(?:$_regionCodes)\\s*\\)|(?:$_regionCodes)\\s*[:|]\\s*|\\|\\s*(?:$_regionCodes)\\s*\\|)\\s*',
      caseSensitive: false);

  static final _trailingRegion = RegExp(
      '\\s*(?:\\|\\s*(?:$_regionCodes)\\s*\\||\\[\\s*(?:$_regionCodes)\\s*\\]|\\(\\s*(?:$_regionCodes)\\s*\\)|\\s[|:]\\s*(?:$_regionCodes))\\s*\$',
      caseSensitive: false);

  /// A programme-type word fenced by separators, or alone at either end:
  /// `| SPT |`, `NEWS:`, `MOVIES |`.
  static final _categoryLabel = RegExp(
      r'(^|[\|:•·])\s*\b(?:' + categoryWords.join('|') + r')\b\s*(?=[\|:•·]|$)',
      caseSensitive: false);

  /// "001 | ", "23. ", "7 - " in front of the real name.
  static final _numbering = RegExp(r'^\s*\d{1,4}\s*[|.\-–—:]\s*');

  /// Whole words only, so "HDTV" and "ESPN2" are left alone.
  static final _quality = RegExp(
      r'[\s|(\[-]*\b(?:(?:f|u)?hd|sd|4k|8k|hdr|hevc|h\.?26[45]|x26[45]|raw|\d{3,4}p)\b[\s|)\]-]*',
      caseSensitive: false);

  static final _repeatedSeparators = RegExp(r'(?:\s*[|•·]\s*){2,}');
  static final _paddedSeparator = RegExp(r'\s*[|•·]\s*');
  static final _edgeSeparators = RegExp(r'^[\s|•·:/,\-–—]+|[\s|•·:/,\-–—]+$');
}
