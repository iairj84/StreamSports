library;

import '../models/channel.dart';
import '../models/epg_program.dart';

/// Catch-up (timeshift) URL building for M3U and Xtream live channels.
///
/// Two provider dialects, one entry point ([catchupUrlFor]):
///
/// * M3U `catchup="default|append|shift"` appends
///   `?utc=<start epoch>&lutc=<minutes>` to the live URL. A `catchup-source`
///   template wins over that when the provider supplies one.
/// * Xtream (`tv_archive=1`, stored as mode `'xc'`) uses the panel's
///   timeshift endpoint:
///   `{server}/timeshift/{user}/{pass}/{minutes}/{yyyy-MM-dd:HH-mm}/{id}.m3u8`.
///   The server, credentials, and stream id are derived from the channel's
///   own live URL (`…​/live/{user}/{pass}/{id}.ts`), so no extra state is
///   needed at playback time.
///
/// Modes this file does not know (e.g. `flussonic`) only play when a
/// `catchup-source` template is present — guessing any other shape would
/// just produce a confident-looking broken stream.
const _utcLutcModes = {'default', 'append', 'shift'};

/// How far back catch-up reaches when the provider advertises support but
/// no day count. Three days matches the common panel/M3U default.
const defaultCatchupDays = 3;

/// A resolved catch-up request: play [start] for [durationMinutes] minutes.
class CatchupRange {
  const CatchupRange(this.start, this.durationMinutes);
  final DateTime start;
  final int durationMinutes;
}

/// Earliest playable instant for [channel] relative to [now].
DateTime catchupEarliest(Channel channel, DateTime now) =>
    now.subtract(Duration(days: channel.catchupDays ?? defaultCatchupDays));

/// Resolves what "watch from start" means for [channel]:
/// [program]'s slot when one is given (clamped to the catch-up window and
/// to "already aired"), otherwise a bounded rewind so guide-less setups
/// still get a working restart. Null when nothing sensible resolves —
/// e.g. the programme predates the archive window.
CatchupRange? catchupRangeFor(Channel channel,
    {EpgProgram? program, DateTime? now}) {
  if (!channel.hasCatchup) return null;
  now ??= DateTime.now();
  final earliest = catchupEarliest(channel, now);
  if (program != null) {
    if (program.stop.isBefore(earliest) || !program.start.isBefore(now)) {
      return null;
    }
    final start =
        program.start.isBefore(earliest) ? earliest : program.start;
    final minutes = now.difference(start).inMinutes;
    if (minutes < 1) return null;
    return CatchupRange(start, minutes);
  }
  final window = now.difference(earliest);
  const fallback = Duration(hours: 3);
  final rewind = window < fallback ? window : fallback;
  if (rewind.inMinutes < 1) return null;
  return CatchupRange(now.subtract(rewind), rewind.inMinutes);
}

/// True when [channel] can restart now — catch-up advertised and a range
/// resolves (the current guide slot, else the bounded fallback rewind).
bool canWatchFromStart(Channel channel,
        {EpgProgram? currentProgram, DateTime? now}) =>
    catchupRangeFor(channel, program: currentProgram, now: now) != null;

/// Builds the playable catch-up URL for [channel] covering [range].
/// Returns null for modes this file cannot construct (see above).
String? catchupUrlFor(Channel channel, CatchupRange range) {
  final mode = channel.catchupMode?.toLowerCase();
  if (mode == null || mode.isEmpty) return null;
  final template = channel.catchupSource;
  if (template != null && template.isNotEmpty) {
    return _fillTemplate(template, channel, range);
  }
  if (_utcLutcModes.contains(mode)) {
    final sep = channel.url.contains('?') ? '&' : '?';
    final start = range.start.millisecondsSinceEpoch ~/ 1000;
    return '${channel.url}${sep}utc=$start&lutc=${range.durationMinutes}';
  }
  if (mode == 'xc') return _xtreamTimeshiftUrl(channel.url, range);
  return null;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `…​/live/{user}/{pass}/{id}.{ext}` →
/// `…​/timeshift/{user}/{pass}/{minutes}/{yyyy-MM-dd:HH-mm}/{id}.m3u8`.
/// Null when the live URL is not in that shape (renamed/custom URLs).
String? _xtreamTimeshiftUrl(String liveUrl, CatchupRange range) {
  final uri = Uri.tryParse(liveUrl);
  if (uri == null || uri.pathSegments.length < 4) return null;
  final segs = uri.pathSegments;
  final live = segs.indexOf('live');
  if (live < 0 || live + 3 != segs.length - 1) return null;
  final user = segs[live + 1], pass = segs[live + 2];
  if (user.isEmpty || pass.isEmpty) return null;
  var id = segs.last;
  final dot = id.lastIndexOf('.');
  if (dot > 0) id = id.substring(0, dot);
  if (id.isEmpty) return null;
  final s = range.start;
  final start =
      '${s.year.toString().padLeft(4, '0')}-${_two(s.month)}-${_two(s.day)}:'
      '${_two(s.hour)}-${_two(s.minute)}';
  return uri
      .replace(
          pathSegments: [
        ...segs.sublist(0, live),
        'timeshift',
        user,
        pass,
        '${range.durationMinutes}',
        start,
        '$id.m3u8'
      ])
      .toString();
}

/// Fills a provider `catchup-source` template. Supported placeholders:
/// `${start}`/`${timestamp}` (epoch seconds), `${end}`, `${offset}`
/// (start relative to now, seconds), `${duration}`/`${lutc}` (minutes).
/// Null when the template needs something unresolvable here
/// (`{catchup-id}` and friends), rather than emitting a broken URL.
String? _fillTemplate(String template, Channel channel, CatchupRange range) {
  final start = range.start.millisecondsSinceEpoch ~/ 1000;
  var out = template
      .replaceAll('\${start}', '$start')
      .replaceAll('\${timestamp}', '$start')
      .replaceAll('\${offset}', '${range.start.difference(DateTime.now()).inSeconds}')
      .replaceAll('\${duration}', '${range.durationMinutes}')
      .replaceAll('\${lutc}', '${range.durationMinutes}');
  final end = start + range.durationMinutes * 60;
  out = out.replaceAll('\${end}', '$end');
  // Anything left in braces is a variable this file cannot resolve.
  if (RegExp(r'\{[^}]*\}').hasMatch(out)) return null;
  return out;
}
