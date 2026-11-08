import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/services/launcher_icon_export.dart';

/// Serves the bytes of one bundled asset, so the test never touches disk.
class _Bundle extends AssetBundle {
  _Bundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';

  @override
  Future<T> loadStructuredData<T>(
          String key, Future<T> Function(String value) parser) async =>
      parser('');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(LauncherIconExport.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends the bundled bytes and the target file name', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 9, 9]);
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return 'saved';
    });

    final export = LauncherIconExport(bundle: _Bundle(bytes), channel: channel);
    final outcome = await export.save(launcherIconArt.first);

    expect(outcome, LauncherIconSave.saved);
    expect(seen!.method, 'saveImage');
    final args = seen!.arguments as Map;
    expect(args['bytes'], bytes);
    expect(args['name'], launcherIconArt.first.fileName);
    expect(args['mime'], 'image/png');
  });

  test('a refused permission is reported, not thrown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 'permission');
    final export = LauncherIconExport(
        bundle: _Bundle(Uint8List.fromList([1, 2])), channel: channel);
    expect(await export.save(launcherIconArt[1]),
        LauncherIconSave.permissionDenied);
  });

  test('a platform failure and a missing channel stay distinct', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 'failed');
    final export = LauncherIconExport(
        bundle: _Bundle(Uint8List.fromList([1])), channel: channel);
    expect(await export.save(launcherIconArt.first), LauncherIconSave.failed);

    final noChannel = LauncherIconExport(
        bundle: _Bundle(Uint8List.fromList([1])),
        channel: const MethodChannel('com.nox.nox_iptv/absent'));
    expect(await noChannel.save(launcherIconArt.first),
        LauncherIconSave.unavailable);
  });

  test('every artwork entry names a bundled asset', () {
    expect(launcherIconArt, hasLength(4));
    for (final art in launcherIconArt) {
      expect(art.asset, startsWith('assets/icon/'));
      expect(art.fileName, endsWith('.png'));
    }
  });
}
