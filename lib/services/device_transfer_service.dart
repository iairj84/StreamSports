import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'settings_bundle.dart';
import 'storage_service.dart';

/// Settings transfer between two devices on the same Wi-Fi, with no server in
/// between. The receiving device listens, the sending device finds it by UDP
/// broadcast, and the payload is sealed with an ephemeral X25519 exchange and
/// AES-256-GCM. Both screens show the same six-digit code derived from the
/// handshake, so a device that is not the one in the other hand is visible
/// before anything is replaced.
///
/// The transfer *replaces* the receiver's playlists, settings, sports picks and
/// lists. Device-only keys (resume positions, update checks, caches) are never
/// sent and never cleared.
const String kTransferMarker = 'nox-transfer/1';
const int kTransferDiscoveryPort = 47826;
const Duration kTransferApprovalWindow = Duration(minutes: 2);

/// A receiver found on the local network.
class TransferPeer {
  const TransferPeer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.token,
    required this.publicKey,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final String token;
  final List<int> publicKey;

  Uri _endpoint(String path) => Uri.parse('http://$address:$port/p/$token/$path');
}

/// The code both devices must show, derived from the exchanged keys and the
/// session id — a device in the middle cannot make both screens agree.
String transferCode(List<int> peerKeyA, List<int> peerKeyB, String sessionId) {
  final ordered = [base64Url.encode(peerKeyA), base64Url.encode(peerKeyB)]
    ..sort();
  final digest = crypto.sha256.convert(utf8.encode(
      '$kTransferMarker|$sessionId|${ordered[0]}|${ordered[1]}'));
  final value = (digest.bytes[0] << 16) | (digest.bytes[1] << 8) | digest.bytes[2];
  final code = (value % 1000000).toString().padLeft(6, '0');
  return '${code.substring(0, 3)} ${code.substring(3)}';
}

/// X25519 + HKDF + AES-256-GCM for one session. Keys live only in memory.
class TransferCipher {
  TransferCipher({SimpleKeyPair? keyPair, this.sessionId = ''})
      : _keyPair = keyPair;

  SimpleKeyPair? _keyPair;
  final String sessionId;
  final _x25519 = X25519();
  SecretKey? _key;

  Future<List<int>> ensureKeyPair() async {
    final pair = _keyPair ??= await _x25519.newKeyPair();
    return await pair.extractPublicKey().then((k) => k.bytes);
  }

  /// Derive the session key from our private key and the peer's public key.
  Future<void> derive(List<int> peerPublicKey) async {
    final pair = _keyPair ??= await _x25519.newKeyPair();
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey:
          SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(sessionId),
      info: utf8.encode('$kTransferMarker settings'),
    );
    _key = SecretKey(await derived.extractBytes());
  }

  Future<String> seal(String plaintext) async {
    final key = _key;
    if (key == null) throw StateError('no session key');
    final box = await AesGcm.with256bits()
        .encrypt(utf8.encode(plaintext), secretKey: key);
    return jsonEncode({
      'iv': base64.encode(box.nonce),
      'ct': base64.encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  /// Null on tampering, a wrong key, or garbage — never a partial result.
  Future<String?> open(String sealed) async {
    final key = _key;
    if (key == null) return null;
    try {
      final json = jsonDecode(sealed) as Map<String, dynamic>;
      final iv = base64.decode(json['iv'] as String);
      final ct = base64.decode(json['ct'] as String);
      if (ct.length < 16) return null;
      final box = SecretBox(ct.sublist(0, ct.length - 16),
          nonce: iv, mac: Mac(ct.sublist(ct.length - 16)));
      final clear =
          await AesGcm.with256bits().decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      debugPrint('Transfer: payload rejected: ${e.runtimeType}');
      return null;
    }
  }
}

/// The receiving side: broadcasts itself, listens for a sender, shows the code,
/// waits for local approval, then replaces this device's configuration.
class TransferReceiver {
  TransferReceiver(this._storage, {this.deviceName = 'This device'});

  final StorageService _storage;
  final String deviceName;

  RawDatagramSocket? _udp;
  HttpServer? _http;
  String? _address;
  int? _port;
  TransferCipher? _cipher;
  late final String _sessionId = _randomToken(16);
  late final String _token = _randomToken(12);
  List<int> _publicKey = const [];

  final _status = StreamController<ReceiverStatus>.broadcast();
  Stream<ReceiverStatus> get status => _status.stream;
  ReceiverStatus _current = const ReceiverStatus(phase: TransferPhase.idle);
  ReceiverStatus get current => _current;

  /// Exposed for the loopback test that drives a real exchange in one process.
  String get sessionId => _sessionId;
  String get token => _token;
  List<int> get publicKey => _publicKey;
  int? get port => _port;

  Completer<bool>? _approval;
  String? _code;


  void _emit(ReceiverStatus status) {
    _current = status;
    if (!_status.isClosed) _status.add(status);
  }

  /// Start broadcasting and listening. Completion of the returned future means
  /// the device is discoverable — not that anyone is connected.
  Future<void> start(
      {InternetAddress? bindAddress, bool discovery = true}) async {
    if (_http != null) return;
    final cipher = _cipher = TransferCipher(sessionId: _sessionId);
    _publicKey = await cipher.ensureKeyPair();
    final host = bindAddress ?? await _lanAddress();
    if (host == null) throw StateError('No Wi-Fi network found');
    final server = await HttpServer.bind(
        bindAddress ?? InternetAddress.anyIPv4, 0,
        shared: false);
    _http = server;
    _port = server.port;
    _address = host.address;
    server.listen(_handle, onError: (Object e) {
      debugPrint('Transfer: server error ${e.runtimeType}');
    });
    if (discovery) await _openDiscovery(host);
    _emit(ReceiverStatus(
        phase: TransferPhase.waiting,
        address: '${host.address}:${server.port}'));
  }

  Future<void> _openDiscovery(InternetAddress host) async {
    try {
      final socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, kTransferDiscoveryPort,
              reuseAddress: true, reusePort: false);
      _udp = socket;
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final probe = _decode(datagram.data);
        if (probe == null || probe['t'] != 'probe') return;
        final reply = jsonEncode({
          'm': kTransferMarker,
          't': 'offer',
          'id': _sessionId,
          'name': deviceName,
          'port': _port,
          'token': _token,
          'pk': base64Url.encode(_publicKey),
        });
        socket.send(utf8.encode(reply), datagram.address, datagram.port);
      });
    } catch (e) {
      // Discovery is best effort: a firewall may block UDP while the code path
      // (address typed in) still works.
      debugPrint('Transfer: discovery unavailable: ${e.runtimeType}');
    }
  }

  /// Accept the sender's request: replaces this device's configuration.
  Future<void> approve() async {
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(true);
  }

  Future<void> reject() async {
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(false);
    _emit(const ReceiverStatus(phase: TransferPhase.waiting));
  }

  Future<void> stop() async {
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(false);
    _approval = null;
    await _http?.close(force: true);
    _http = null;
    _udp?.close();
    _udp = null;
    _emit(const ReceiverStatus(phase: TransferPhase.idle));
    await _status.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    try {
      if (request.uri.pathSegments.length != 3 ||
          request.uri.pathSegments[0] != 'p' ||
          request.uri.pathSegments[1] != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final body =
          await _readLimited(request, SettingsBundle.maxBytes + 65536);
      if (body == null) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      switch (request.uri.pathSegments[2]) {
        case 'hello':
          await _hello(body, response);
        case 'bundle':
          await _receiveBundle(body, response);
        default:
          response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      debugPrint('Transfer: request failed: ${e.runtimeType} $e');
      response.statusCode = HttpStatus.internalServerError;
      if (_current.phase != TransferPhase.done) {
        _emit(ReceiverStatus(
            phase: TransferPhase.failed,
            address: _address,
            message: 'The transfer stopped: ${e.toString()}'));
      }
    } finally {
      await response.close();
    }
  }

  Future<void> _hello(String body, HttpResponse response) async {
    final json = _decode(body);
    final name = (json?['name'] as String?)?.trim() ?? '';
    final key = json?['pk'];
    if (json == null || key is! String || name.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final peerKey = base64Url.decode(key);
    if (peerKey.length != 32) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final cipher = _cipher;
    if (cipher == null) {
      response.statusCode = HttpStatus.conflict;
      return;
    }
    _code = transferCode(_publicKey, peerKey, _sessionId);
    await cipher.derive(peerKey);
    final approval = _approval = Completer<bool>();
    _emit(ReceiverStatus(
      phase: TransferPhase.approval,
      address: _address,
      code: _code,
      peerName: name,
    ));
    final approved = await approval.future
        .timeout(kTransferApprovalWindow, onTimeout: () => false);
    _approval = null;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({
      'approved': approved,
      'code': _code,
      'pk': base64Url.encode(_publicKey),
    }));
    if (!approved) {
      _emit(const ReceiverStatus(phase: TransferPhase.waiting));
    }
  }

  Future<void> _receiveBundle(String body, HttpResponse response) async {
    final cipher = _cipher;
    if (cipher == null) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final json = _decode(body);
    final sealed = json?['payload'];
    if (sealed is! String) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final clear = await cipher.open(sealed);
    if (clear == null) {
      response.statusCode = HttpStatus.badRequest;
      _emit(ReceiverStatus(
          phase: TransferPhase.failed,
          address: _address,
          message: 'The data did not arrive intact. Nothing was changed.'));
      return;
    }
    final bundle = SettingsBundle.fromJson(jsonDecode(clear));
    if (bundle == null) {
      response.statusCode = HttpStatus.badRequest;
      _emit(ReceiverStatus(
          phase: TransferPhase.failed,
          address: _address,
          message: 'That device sent settings this version cannot read.'));
      return;
    }
    debugPrint('Transfer: applying ${bundle.byteLength} bytes');
    _emit(ReceiverStatus(phase: TransferPhase.receiving, address: _address));
    late final TransferReport report;
    try {
      report = await bundle.applyTo(_storage);
    } catch (e) {
      debugPrint('Transfer: apply failed: $e');
      response.statusCode = HttpStatus.internalServerError;
      _emit(ReceiverStatus(
          phase: TransferPhase.failed,
          address: _address,
          message: 'Saving the settings failed: ${e.toString()}'));
      return;
    }
    debugPrint('Transfer: applied ${report.values} settings');
    _emit(ReceiverStatus(
        phase: TransferPhase.done, address: _address, report: report));
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(report.toJson()));
  }

  void dispose() {
    _udp?.close();
    _http?.close(force: true);
    if (!_status.isClosed) _status.close();
  }
}

/// The sending side: find receivers, confirm the code, then send this device's
/// configuration. Nothing is written on this device.
class TransferSender {
  TransferSender(this._storage, {this.deviceName = 'This device'});

  final StorageService _storage;
  final String deviceName;

  final _devices = StreamController<List<TransferPeer>>.broadcast();
  Stream<List<TransferPeer>> get devices => _devices.stream;

  RawDatagramSocket? _udp;
  final _found = <String, TransferPeer>{};

  Future<void> discover({Duration window = const Duration(seconds: 8)}) async {
    _found.clear();
    final socket = _udp ??= await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 0,
        reuseAddress: true);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      final offer = datagram == null ? null : _decode(datagram.data);
      if (offer == null || offer['t'] != 'offer') return;
      final key = offer['pk'];
      final port = offer['port'];
      final token = offer['token'];
      final id = offer['id'];
      if (key is! String || port is! int || token is! String || id is! String) {
        return;
      }
      final peer = TransferPeer(
        id: id,
        name: '${offer['name'] ?? 'Device'}',
        address: datagram!.address.address,
        port: port,
        token: token,
        publicKey: base64Url.decode(key),
      );
      _found[peer.id] = peer;
      if (!_devices.isClosed) _devices.add(_found.values.toList());
    });
    final probe = utf8.encode(jsonEncode({'m': kTransferMarker, 't': 'probe'}));
    socket.send(probe, InternetAddress('255.255.255.255'), kTransferDiscoveryPort);
    await Future<void>.delayed(window);
    socket.send(probe, InternetAddress('255.255.255.255'), kTransferDiscoveryPort);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// Ask the receiver to accept a transfer. Returns its code when it does.
  Future<SenderHandshake> request(TransferPeer peer) async {
    final senderCipher = TransferCipher(sessionId: peer.id);
    final myKey = await senderCipher.ensureKeyPair();
    final response = await http
        .post(peer._endpoint('hello'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'name': deviceName, 'pk': base64Url.encode(myKey)}))
        .timeout(kTransferApprovalWindow + const Duration(seconds: 10));
    final json = _decode(response.body);
    if (response.statusCode != 200 || json == null) {
      throw StateError('The other device did not answer.');
    }
    if (json['approved'] != true) {
      return SenderHandshake(approved: false, code: '${json['code'] ?? ''}', cipher: senderCipher);
    }
    await senderCipher.derive(peer.publicKey);
    final code = '${json['code'] ?? ''}';
    final mine = transferCode(peer.publicKey, myKey, peer.id);
    return SenderHandshake(
        approved: code == mine, code: code, cipher: senderCipher);
  }

  /// Send the chosen sections. The receiver applies them and reports back.
  Future<TransferReport?> send(
      TransferPeer peer, SenderHandshake handshake,
      {required Set<TransferSection> sections}) async {
    if (!handshake.approved) return null;
    final bundle = SettingsBundle.capture(_storage, sections: sections);
    debugPrint('Transfer: sending ${bundle.byteLength} bytes');
    if (bundle.tooLarge) {
      throw StateError(
          'These settings are too large to send (${bundle.megabyteCount} MB).');
    }
    final sealed = await handshake.cipher.seal(bundle.encode());
    final response = await http
        .post(peer._endpoint('bundle'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'payload': sealed}))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw StateError('The other device could not save the settings.');
    }
    final json = _decode(response.body) ?? const {};
    return TransferReport(
      values: (json['values'] as num?)?.toInt() ?? 0,
      removed: (json['removed'] as num?)?.toInt() ?? 0,
      sections: {
        for (final name in (json['sections'] as List? ?? const []))
          if (name is String)
            for (final section in TransferSection.values)
              if (section.name == name) section
      },
    );
  }

  void dispose() {
    _udp?.close();
    if (!_devices.isClosed) _devices.close();
  }
}

class SenderHandshake {
  const SenderHandshake(
      {required this.approved, required this.code, required this.cipher});
  final bool approved;
  final String code;
  final TransferCipher cipher;
}

enum TransferPhase { idle, waiting, approval, receiving, done, failed }

class ReceiverStatus {
  const ReceiverStatus(
      {required this.phase, this.address, this.code, this.peerName, this.report, this.message});
  final TransferPhase phase;
  final String? address;
  final String? code;
  final String? peerName;
  final TransferReport? report;
  final String? message;
}

/// At most [max] bytes of a request body; null when the sender exceeded it.
Future<String?> _readLimited(HttpRequest request, int max) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > max) return null;
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _decode(Object? data) {
  try {
    final text = data is String ? data : utf8.decode(data as List<int>);
    final json = jsonDecode(text);
    if (json is! Map) return null;
    return json.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

Future<InternetAddress?> _lanAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      if (name.startsWith('tun') ||
          name.startsWith('utun') ||
          name.startsWith('wg') ||
          name.contains('virtual')) {
        continue;
      }
      for (final address in interface.addresses) {
        final b = address.rawAddress;
        if (b.length != 4) continue;
        if (b[0] == 10 ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168)) {
          return address;
        }
      }
    }
  } catch (_) {}
  return null;
}

String _randomToken(int n) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(n, (_) => alphabet[random.nextInt(alphabet.length)])
      .join();
}
