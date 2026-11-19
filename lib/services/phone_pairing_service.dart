import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// Optional self-hosted relay. LAN pairing works without a relay.
const String kPairRelayBase = String.fromEnvironment('PAIR_RELAY_BASE');

/// Protocol marker understood by the bundled relay implementation; not a secret.
const Map<String, String> kRelayAppHeaders = {'X-VesperTV-App': '1'};

/// Base64 of [SettingsBundle.maxBytes] is about 21 MB. Anything past this cap
/// is not a backup file this app wrote.
const int _maxBackupChars = 24 * 1024 * 1024;

/// What a pairing session asks the phone for: the Add Playlist form, a whole
/// first-run setup (playlist plus appearance and update choices), one long
/// link (Settings > Archive sources' manifest URL), a batch of channel names
/// (Settings > Channel names), or moving a backup file (Settings > Backup &
/// restore). pair.html picks its form from a `.link` / `#link`, `.names` /
/// `#names`, `.backup` / `#backup` or `.setup` / `#setup` suffix on the URL
/// fragment.
enum PairingKind { playlist, setup, link, names, backup }

/// What the phone sent: the same fields Add Playlist has, one [link], or the
/// channel names it edited.
class PairingResult {
  const PairingResult({
    required this.mode,
    this.link = '',
    this.name = '',
    this.server = '',
    this.username = '',
    this.password = '',
    this.m3uUrl = '',
    this.epgUrl = '',
    this.renames = const [],
    this.backupName = '',
    this.backupData = '',
    this.portalUrl = '',
    this.portalMac = '',
    this.portalUsername = '',
    this.portalPassword = '',
    this.includeLive = true,
    this.includeMovies = true,
    this.includeSeries = true,
    this.settings = const {},
    this.fromSetup = false,
  });

  /// 'xtream', 'm3u' or 'link'.
  final String mode;

  /// Set when [mode] is 'link'.
  final String link;
  final String name;
  final String server;
  final String username;
  final String password;
  final String m3uUrl;
  final String epgUrl;

  /// Set when [mode] is 'names': what the phone typed for each channel id.
  final List<({String id, String name})> renames;

  /// Set when [mode] is 'backup': the file's name and its base64 contents.
  final String backupName;
  final String backupData;

  /// Set when [mode] is 'stalker'.
  final String portalUrl;
  final String portalMac;
  final String portalUsername;
  final String portalPassword;

  /// Content choices for Xtream and Stalker; true for M3U, which has no
  /// separate movie or series lists.
  final bool includeLive;
  final bool includeMovies;
  final bool includeSeries;

  /// Which settings the phone chose during setup, keyed by
  /// [setupSettingKeys]. Empty outside a setup session.
  final Map<String, String> settings;

  /// True for a setup payload: [mode] is the playlist kind it carries.
  final bool fromSetup;

  /// The keys a setup page may set. Anything else is dropped on the way in,
  /// so a stale or hand-edited page cannot write an arbitrary preference.
  static const List<String> setupSettingKeys = [
    'palette',
    'surface',
    'clock24',
    'scores',
    'update',
  ];

  PairingResult copyWith(
          {Map<String, String>? settings, bool? fromSetup}) =>
      PairingResult(
        mode: mode,
        link: link,
        name: name,
        server: server,
        username: username,
        password: password,
        m3uUrl: m3uUrl,
        epgUrl: epgUrl,
        renames: renames,
        backupName: backupName,
        backupData: backupData,
        portalUrl: portalUrl,
        portalMac: portalMac,
        portalUsername: portalUsername,
        portalPassword: portalPassword,
        includeLive: includeLive,
        includeMovies: includeMovies,
        includeSeries: includeSeries,
        settings: settings ?? this.settings,
        fromSetup: fromSetup ?? this.fromSetup,
      );

  /// Null when the payload isn't something the form could have produced.
  static PairingResult? fromJson(Object? json) {
    if (json is! Map) return null;
    String s(String k, int max) {
      final v = json[k];
      if (v is! String) return '';
      final t = v.trim();
      return t.length > max ? t.substring(0, max) : t;
    }

    final mode = s('mode', 10);
    // A setup payload nests the playlist it already knows how to read and
    // adds the settings the phone chose alongside it.
    if (mode == 'setup') {
      final inner = fromJson(json['playlist']);
      if (inner == null || inner.fromSetup) return null;
      if (inner.mode != 'xtream' &&
          inner.mode != 'm3u' &&
          inner.mode != 'stalker') {
        return null;
      }
      final chosen = <String, String>{};
      final raw = json['settings'];
      if (raw is Map) {
        for (final key in setupSettingKeys) {
          final value = raw[key];
          if (value is! String) continue;
          final trimmed = value.trim().toLowerCase();
          if (trimmed.isEmpty || trimmed.length > 40) continue;
          chosen[key] = trimmed;
        }
      }
      return inner.copyWith(settings: chosen, fromSetup: true);
    }
    if (mode == 'names') {
      final raw = json['renames'];
      if (raw is! List) return null;
      final renames = <({String id, String name})>[];
      for (final entry in raw.take(500)) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final name = entry['name'];
        if (id is! String || name is! String) continue;
        final trimmedId = id.trim();
        final trimmedName = name.trim();
        if (trimmedId.isEmpty ||
            trimmedId.length > 200 ||
            trimmedName.length > 80) {
          continue;
        }
        renames.add((id: trimmedId, name: trimmedName));
      }
      return renames.isEmpty
          ? null
          : PairingResult(mode: 'names', renames: renames);
    }
    if (mode == 'backup') {
      final name = s('name', 120);
      final raw = json['data'];
      final data = raw is String ? raw.trim() : '';
      // Base64 of SettingsBundle.maxBytes is about 21 MB; anything beyond the
      // hard cap is not a backup this app wrote.
      if (data.isEmpty || data.length > _maxBackupChars) return null;
      return PairingResult(mode: 'backup', backupName: name, backupData: data);
    }
    bool b(String k) {
      final v = json[k];
      if (v is bool) return v;
      if (v is String) return v.trim().toLowerCase() != 'false';
      return true;
    }

    final r = PairingResult(
      mode: mode,
      name: s('name', 80),
      server: s('server', 500),
      username: s('username', 200),
      password: s('password', 200),
      m3uUrl: s('m3u', 2000),
      epgUrl: s('epg', 2000),
      link: s('link', 4000),
      portalUrl: s('portalUrl', 500),
      portalMac: s('portalMac', 64),
      portalUsername: s('portalUsername', 200),
      portalPassword: s('portalPassword', 200),
      includeLive: b('live'),
      includeMovies: b('movies'),
      includeSeries: b('series'),
    );
    if (mode == 'link') return r.link.isNotEmpty ? r : null;
    if (mode == 'stalker') {
      return r.portalUrl.isNotEmpty && r.portalMac.isNotEmpty ? r : null;
    }
    if (mode == 'xtream' &&
        r.server.isNotEmpty &&
        r.username.isNotEmpty &&
        r.password.isNotEmpty) {
      return r;
    }
    if (mode == 'm3u' && r.m3uUrl.isNotEmpty) return r;
    return null;
  }
}

/// Add Playlist > "From my phone": the TV shows a QR code, the phone opens a
/// form, and what's typed there lands back in the TV's Add Playlist fields.
///
/// Two ways in, because the TV can't know which network the phone is on:
/// - **Wi-Fi (default):** the TV runs a one-session HTTP server on its LAN
///   address and the QR opens `http://<tv-ip>:<port>/p/<token>` — nothing
///   leaves the home network.
/// - **Relay (fallback, phone on mobile data):** the QR opens the relay page
///   with `#<sessionId>.<key>` in the fragment (never sent to any server);
///   the phone AES-GCM-encrypts the form and uploads only ciphertext, which
///   the TV polls for and decrypts here.
///
/// Both stay armed together once started (one result wins), the server is
/// closed on [stop], and everything expires after [lifetime].
class PhonePairingSession {
  PhonePairingSession(
      {this.lifetime = const Duration(minutes: 10),
      this.kind = PairingKind.playlist,
      this.channels,
      this.backupList,
      this.backupBytes,
      this.backupRestore = false,
      this.palette,
      this.surface});

  final Duration lifetime;

  /// Which form the phone shows; results of the other kind are refused.
  final PairingKind kind;

  /// The channels the phone may rename, served to it over the TV's own LAN
  /// server. Only used by [PairingKind.names], which is Wi-Fi only: the relay
  /// can carry a phone's upload but cannot hand it this list.
  final List<Map<String, String>> Function()? channels;

  /// [PairingKind.backup]: one entry per saved backup, as `{name, bytes, at}`.
  /// Served over the TV's LAN server only, like [channels], because the relay
  /// cannot hand files back to a phone.
  final Future<List<Map<String, Object>>> Function()? backupList;

  /// [PairingKind.backup]: the bytes of one listed backup, or null when the
  /// name is not one this device just offered.
  final Future<List<int>?> Function(String name)? backupBytes;

  /// Opens the phone page on its Restore side instead of Save, which is what a
  /// new device needs.
  final bool backupRestore;

  /// This device's current look (`CyberpunkPalette.id` and
  /// `SurfaceStyle.name`). The phone page is a screen of this app, so it is
  /// painted in the same palette and surface style instead of a generic web
  /// form; null paints the shipped default. Sent in the URL query, which the
  /// relay and the LAN server both ignore when routing.
  final String? palette;
  final String? surface;

  /// The URL-fragment suffix pair.html reads (see [PairingKind]).
  String get _kindSuffix => switch (kind) {
        PairingKind.link => 'link',
        PairingKind.names => 'names',
        PairingKind.backup => 'backup',
        PairingKind.setup => 'setup',
        PairingKind.playlist => '',
      };

  /// Whether [r] belongs to this session's kind. Exposed for tests: the
  /// refusal rules are what keep a stale phone page from writing settings a
  /// playlist-only session never offered, and opening a real server to prove
  /// them would test the socket, not the rule.
  @visibleForTesting
  bool acceptsResult(PairingResult r) => _accepts(r);

  bool _accepts(PairingResult r) => switch (kind) {
        PairingKind.link => r.mode == 'link',
        PairingKind.names => r.mode == 'names',
        PairingKind.backup => r.mode == 'backup',
        PairingKind.setup => r.fromSetup,
        // A setup payload carries a playlist mode too, but only a setup
        // session may apply its settings.
        PairingKind.playlist => !r.fromSetup &&
            r.mode != 'link' &&
            r.mode != 'names' &&
            r.mode != 'backup',
      };

  final _results = StreamController<PairingResult>.broadcast();
  Stream<PairingResult> get results => _results.stream;

  HttpServer? _server;
  String? _lanUrl;
  late final String _token = _randomToken(8);
  late final List<int> _key = _randomBytes(32);
  late final String _sessionId = _b64url(_randomBytes(16));
  Timer? _relayPoll;
  Timer? _expiry;
  bool _done = false;
  String? _pageHtml;

  /// `http://<ip>:<port>/p/<token>`, or null when the TV has no private
  /// IPv4 address (then only the relay path can work).
  String? get lanUrl => _lanUrl;

  /// Query string the phone page reads: this device's look, plus which side
  /// of the backup screen to open. It stays before the fragment, which
  /// carries the relay key and the kind suffix and is never sent anywhere.
  String get _lookQuery {
    final params = <String>[
      if (palette != null && palette!.isNotEmpty)
        'p=${Uri.encodeQueryComponent(palette!)}',
      if (surface != null && surface!.isNotEmpty)
        's=${Uri.encodeQueryComponent(surface!)}',
      if (kind == PairingKind.backup && backupRestore) 'b=restore',
    ];
    return params.isEmpty ? '' : '?${params.join('&')}';
  }

  String get relayUrl =>
      '$kPairRelayBase/p$_lookQuery#$_sessionId.${_b64url(_key)}'
      '${_kindSuffix.isEmpty ? '' : '.$_kindSuffix'}';

  bool get isExpired => _done;

  Future<void> start() async {
    _expiry = Timer(lifetime, stop);
    _pageHtml = await rootBundle.loadString('assets/pair/pair.html');
    final ip = await _privateIpv4();
    if (ip == null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _lanUrl = 'http://${ip.address}:${server.port}/p/$_token$_lookQuery'
          '${_kindSuffix.isEmpty ? '' : '#$_kindSuffix'}';
      server.listen(_handle, onError: (Object e) {
        debugPrint('PhonePairing: server error ${e.runtimeType}');
      });
    } catch (e) {
      debugPrint(
          'PhonePairing: could not open the local server: ${e.runtimeType}');
    }
  }

  /// Starts polling the relay (only while the relay QR is on screen, so a
  /// Wi-Fi-only pairing never touches the VPS).
  void startRelayPolling() {
    if (kPairRelayBase.isEmpty || _done || _relayPoll != null) return;
    _relayPoll =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollRelay());
  }

  void stopRelayPolling() {
    _relayPoll?.cancel();
    _relayPoll = null;
  }

  Future<void> stop() async {
    _done = true;
    stopRelayPolling();
    _expiry?.cancel();
    final server = _server;
    _server = null;
    await server?.close(force: true);
    if (!_results.isClosed) await _results.close();
  }

  void _deliver(PairingResult r) {
    if (_done || !_accepts(r)) return;
    _results.add(r);
    unawaited(stop());
  }

  // ------------------------------------------------------------- Wi-Fi path

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    PairingResult? received;
    res.headers
      ..set('Cache-Control', 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff');
    try {
      // The names editor reads the channel list through the same one-session
      // server, so the list never leaves the home network.
      if (req.uri.path == '/p/$_token/channels') {
        if (req.method != 'GET') {
          res.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'channels': channels?.call() ?? const []}));
        return;
      }
      if (kind == PairingKind.backup && req.uri.path == '/p/$_token/backups') {
        if (req.method != 'GET') {
          res.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        res.headers.contentType = ContentType.json;
        res.write(
            jsonEncode({'backups': await backupList?.call() ?? const []}));
        return;
      }
      if (kind == PairingKind.backup && req.uri.path == '/p/$_token/backup') {
        if (req.method != 'GET') {
          res.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        final name = req.uri.queryParameters['name'] ?? '';
        // Only a name this device just listed, and never anything that could
        // walk out of the backups folder.
        final usable = name.isNotEmpty &&
            !name.contains('/') &&
            !name.contains(r'\') &&
            !name.contains('..');
        final bytes = usable ? await backupBytes?.call(name) : null;
        if (bytes == null) {
          res.statusCode = HttpStatus.notFound;
          return;
        }
        // A JSON content type and the file name together let Android's file
        // picker keep this as a .json the restore side will offer back.
        res.headers.contentType = ContentType.json;
        res.headers.set('Content-Disposition', 'attachment; filename="$name"');
        res.add(bytes);
        return;
      }
      if (req.uri.path != '/p/$_token') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (_done) {
        res.statusCode = HttpStatus.gone;
        return;
      }
      if (req.method == 'GET') {
        res.headers.contentType = ContentType.html;
        res.write(_pageHtml ?? '');
        return;
      }
      if (req.method != 'POST') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final body = await _readLimited(
          req, kind == PairingKind.backup ? _maxBackupChars : 16 * 1024);
      final result = body == null ? null : _decodeResult(body);
      if (result == null || !_accepts(result)) {
        res.statusCode = HttpStatus.badRequest;
        return;
      }
      res.statusCode = HttpStatus.noContent;
      received = result;
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close();
    }
    // Send the phone response before closing the pairing server, which would otherwise
    // terminate the response connection.
    if (received != null) _deliver(received);
  }

  static Future<String?> _readLimited(HttpRequest req, int max) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > max) return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static PairingResult? _decodeResult(String json) {
    try {
      return PairingResult.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// The address a phone on the same network can reach: the first private
  /// IPv4 (Wi-Fi or Ethernet), skipping loopback and link-local.
  static Future<InternetAddress?> _privateIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      return selectLanAddress(
          interfaces.map((i) => (name: i.name, addresses: i.addresses)));
    } catch (_) {
      return null;
    }
  }

  /// Prefer a physical LAN adapter over an unknown interface, and never
  /// advertise a known VPN tunnel as the phone's local pairing address.
  @visibleForTesting
  static InternetAddress? selectLanAddress(
      Iterable<({String name, Iterable<InternetAddress> addresses})>
          interfaces) {
    InternetAddress? fallback;
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      if (RegExp(r'^(tun|utun|tap|ppp|wg|ipsec|tailscale|vpn|docker|veth|virbr|vbox|vmnet)')
              .hasMatch(name) ||
          name.contains('virtual') ||
          name.contains('vmware')) {
        continue;
      }
      for (final address in interface.addresses) {
        if (!_isPrivate(address)) continue;
        if (RegExp(r'^(wlan|wifi|wi-fi|eth|ethernet|en[0-9]|enp|ens|wlp)')
            .hasMatch(name)) {
          return address;
        }
        fallback ??= address;
      }
    }
    return fallback;
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (b.length != 4) return false;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  // ------------------------------------------------------------- relay path

  bool _polling = false;

  Future<void> _pollRelay() async {
    if (_polling || _done) return;
    _polling = true;
    try {
      final res = await http
          .get(Uri.parse('$kPairRelayBase/api/s/$_sessionId'),
              headers: kRelayAppHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final result = await decryptRelayPayload(res.body, _key);
      if (result != null) _deliver(result);
    } catch (_) {
      // Offline or relay down — keep trying until the session expires.
    } finally {
      _polling = false;
    }
  }

  /// Opens a relay blob (`{"iv","ct"}`, base64) sealed by pair.html's
  /// WebCrypto AES-GCM with [key]. Null on any tampering or garbage.
  @visibleForTesting
  static Future<PairingResult?> decryptRelayPayload(
      String body, List<int> key) async {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final iv = base64.decode(json['iv'] as String);
      final ct = base64.decode(json['ct'] as String);
      if (ct.length < 16) return null;
      // WebCrypto appends the 16-byte GCM tag to the ciphertext.
      final box = SecretBox(ct.sublist(0, ct.length - 16),
          nonce: iv, mac: Mac(ct.sublist(ct.length - 16)));
      final clear =
          await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
      return _decodeResult(utf8.decode(clear));
    } catch (e) {
      debugPrint('PhonePairing: relay payload rejected: ${e.runtimeType}');
      return null;
    }
  }

  // ---------------------------------------------------------------- helpers

  static final _rng = Random.secure();

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Short, unambiguous (no 0/O/1/l) so the Wi-Fi URL can be typed by hand.
  static String _randomToken(int n) {
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    return List.generate(n, (_) => alphabet[_rng.nextInt(alphabet.length)])
        .join();
  }
}

/// The device's private LAN IPv4 (see [PhonePairingSession]); shared with
/// the device-to-device transfer.
Future<InternetAddress?> privateLanIpv4() => PhonePairingSession._privateIpv4();
