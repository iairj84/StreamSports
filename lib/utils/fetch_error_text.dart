/// Credential-free text for a failed provider request.
///
/// `http.ClientException`, `SocketException` and `HandshakeException` put the
/// request URI into their text, and every IPTV URI can carry the viewer's login
/// — in the query (`xmltv.php?username=…&password=…`) or in userinfo. Those
/// strings are shown in Settings, on the home screen and copied into logcat,
/// bug reports and screenshots, so the address is reduced to its origin before
/// it leaves the service. Playback errors have the same problem and their own
/// stricter scrubber in `playback_error_message.dart`; this one keeps the host
/// because a guide or catalogue failure is only actionable with it.
library;

import 'dart:async';

import '../l10n/l10n.dart';

final _address = RegExp(
  r"""\b(?:https?|rtsps?|rtmps?)://[^\s<>"']+""",
  caseSensitive: false,
);

/// A `username=…`, `password=…`, `token=…`, `mac=…` pair that somehow arrived
/// outside a URL (a provider echoing the request, a bare `host:port/path`).
final _credentialPair = RegExp(
  r'(^|[?&;,\s])(?:username|user|password|pass|token|mac|signature|auth)=[^&;\s,)]*',
  caseSensitive: false,
);

/// [error] rendered without any address that could carry provider credentials.
///
/// [url] is the address the request used, for errors whose own text says
/// nothing useful (a bare `TimeoutException`, for instance).
String safeFetchError(Object error, {String? url}) {
  var text = error.toString().replaceAllMapped(_address, _origin);
  text = text.replaceAllMapped(_credentialPair, (match) {
    return '${match[1]}[redacted]';
  });
  final reason = _reason(error);
  if (reason != null) {
    // The port is part of the address a viewer needs: one panel host often
    // serves several subscriptions on different ports.
    final authority = _authority(url) ?? _authorityIn(text);
    return authority == null ? reason : '$reason ($authority)';
  }
  if (text.trim().isEmpty) {
    final host = _hostOf(url);
    return host == null
        ? tr('The request failed.')
        : tr('The request to {host} failed.', {'host': host});
  }
  return text.trim();
}

/// Scheme, host and port only: no userinfo, path or query survives.
String _origin(Match match) {
  final uri = Uri.tryParse(match[0]!);
  if (uri == null || uri.host.isEmpty) return '[address]';
  return uri.hasPort ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
}

String? _hostOf(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  return uri == null || uri.host.isEmpty ? null : uri.host;
}

/// `host:port` of the first address inside arbitrary [text]; parsing the whole
/// text would read "ClientException: ... uri=..." as a URL with no host.
String? _authorityIn(String text) {
  final match = _address.firstMatch(text);
  return match == null ? null : _authority(match[0]);
}

String? _authority(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// Failures whose raw text is pure mechanism ("Connection refused", "timed
/// out") and reads better as one sentence.
String? _reason(Object error) {
  if (error is TimeoutException) {
    return tr('The server did not respond in time.');
  }
  final text = error.toString().toLowerCase();
  if (text.contains('connection refused')) {
    return tr('The server refused the connection.');
  }
  if (text.contains('failed host lookup') ||
      text.contains('unknownhost') ||
      text.contains('unable to resolve host') ||
      text.contains('nodename nor servname')) {
    return tr('The server address could not be found.');
  }
  if (text.contains('network is unreachable') ||
      text.contains('no route to host')) {
    return tr('The server could not be reached.');
  }
  return null;
}
