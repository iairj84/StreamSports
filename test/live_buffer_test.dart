import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/live_buffer.dart';
import 'package:nox_iptv/services/subtitle_tracks.dart';
import 'package:video_player_hdr/video_player_hdr.dart';

class _Controller extends VideoPlayerHdrController {
  _Controller() : super.networkUrl(Uri.parse('https://example.test/video'));
  @override
  int get textureId => 37;
}

Channel _channel(String rawId) => Channel(
    id: 'p::fixture',
    rawId: rawId,
    playlistId: 'p',
    name: 'Fixture',
    group: 'Live',
    url: 'https://example.test/video');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('vespertv/live_buffer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LiveBuffer.ms = 0;
    messenger.setMockMethodCallHandler(methods, null);
  });

  test('the default reaches the player before it is created', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return null;
    });
    await LiveBuffer.setDefault(4000);
    expect(LiveBuffer.ms, 4000);
    expect(calls.single.method, 'setLiveBufferDefault');
    expect(calls.single.arguments, {'ms': 4000});
  });

  test('the reserve applies to live channels and not to a finite stream',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return null;
    });
    LiveBuffer.ms = 8000;
    final controller = _Controller();
    final id = SubtitleTracks.playerIdOf(controller);
    await LiveBuffer.configure(controller, _channel('xt_live_1'));
    await LiveBuffer.configure(controller, _channel('xt_vod_1'));
    expect(calls.map((c) => c.method), ['setLiveBuffer', 'setLiveBuffer']);
    expect(calls.map((c) => c.arguments), [
      {'playerId': id, 'ms': 8000},
      {'playerId': id, 'ms': 0},
    ]);
  });

  test('gradual is forwarded as a negative reserve', () async {
    Object? sent;
    messenger.setMockMethodCallHandler(methods, (call) async {
      sent = call.arguments;
      return null;
    });
    await LiveBuffer.setDefault(-1);
    expect(sent, {'ms': -1});
  });

  test('absent native support does not block playback', () async {
    LiveBuffer.ms = 4000;
    messenger.setMockMethodCallHandler(methods, null);
    await LiveBuffer.configure(_Controller(), _channel('xt_live_1'));
    messenger.setMockMethodCallHandler(methods, (call) async {
      throw PlatformException(code: 'no_player');
    });
    await LiveBuffer.configure(_Controller(), _channel('xt_live_1'));
  });

  test('other platforms are left alone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var called = false;
    messenger.setMockMethodCallHandler(methods, (call) async {
      called = true;
      return null;
    });
    await LiveBuffer.setDefault(4000);
    await LiveBuffer.configure(_Controller(), _channel('xt_live_1'));
    expect(called, isFalse);
  });
}
