import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/services/remote_controls.dart';

KeyDownEvent _press(PhysicalKeyboardKey key) => KeyDownEvent(
    physicalKey: key,
    logicalKey: LogicalKeyboardKey.keyA,
    timeStamp: Duration.zero);

KeyUpEvent _release(PhysicalKeyboardKey key) => KeyUpEvent(
    physicalKey: key,
    logicalKey: LogicalKeyboardKey.keyA,
    timeStamp: Duration.zero);

void main() {
  test('an untouched install binds nothing, so no button is consumed', () {
    final controls = RemoteControls.test();
    expect(controls.isEmpty, isTrue);
    expect(controls.actionFor(_press(PhysicalKeyboardKey.mediaPlayPause)),
        isNull);
  });

  test('a bound button fires once per press, not on release', () {
    final controls = RemoteControls.test()
      ..bind(PhysicalKeyboardKey.mediaPlayPause.usbHidUsage, RemoteAction.sports,
          label: 'Play / pause');
    expect(controls.actionFor(_press(PhysicalKeyboardKey.mediaPlayPause)),
        RemoteAction.sports);
    expect(controls.actionFor(_release(PhysicalKeyboardKey.mediaPlayPause)),
        isNull);
  });

  test('moving an action to a new button frees the old one', () {
    final controls = RemoteControls.test()
      ..bind(PhysicalKeyboardKey.f1.usbHidUsage, RemoteAction.sports, label: 'F1')
      ..bind(PhysicalKeyboardKey.f2.usbHidUsage, RemoteAction.sports, label: 'F2');

    expect(controls.actionFor(_press(PhysicalKeyboardKey.f1)), isNull);
    expect(controls.actionFor(_press(PhysicalKeyboardKey.f2)),
        RemoteAction.sports);
    expect(controls.bindingForAction(RemoteAction.sports)?.label, 'F2');
  });

  test('one button does one thing', () {
    final controls = RemoteControls.test()
      ..bind(PhysicalKeyboardKey.f1.usbHidUsage, RemoteAction.sports, label: 'F1')
      ..bind(PhysicalKeyboardKey.f1.usbHidUsage, RemoteAction.search, label: 'F1');

    expect(controls.actionFor(_press(PhysicalKeyboardKey.f1)),
        RemoteAction.search);
    expect(controls.bindingForAction(RemoteAction.sports), isNull);
  });

  test('saved buttons come back after a reload', () {
    final controls = RemoteControls.test()
      ..bind(PhysicalKeyboardKey.mediaRecord.usbHidUsage, RemoteAction.multiview,
          label: 'Record');
    final saved = controls.toJson();

    final reloaded = RemoteControls.test()..loadFrom(saved);
    expect(reloaded.actionFor(_press(PhysicalKeyboardKey.mediaRecord)),
        RemoteAction.multiview);
    expect(reloaded.bindingForAction(RemoteAction.multiview)?.label, 'Record');
  });

  test('a corrupt or unknown saved map loads as empty instead of throwing', () {
    final controls = RemoteControls.test()..loadFrom('not json');
    expect(controls.isEmpty, isTrue);

    final unknown = RemoteControls.test()
      ..loadFrom('{"42": {"action": "teleport", "label": "F9"}}');
    expect(unknown.isEmpty, isTrue);
  });

  test('reset forgets every remapped button', () {
    final controls = RemoteControls.test()
      ..bind(PhysicalKeyboardKey.f1.usbHidUsage, RemoteAction.sports, label: 'F1')
      ..bind(PhysicalKeyboardKey.f2.usbHidUsage, RemoteAction.settings, label: 'F2')
      ..reset();
    expect(controls.isEmpty, isTrue);
  });

  test('the navigation buttons the app relies on are reserved', () {
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.escape,
    ]) {
      expect(
          isReservedRemoteKey(KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.arrowDown,
              logicalKey: key,
              timeStamp: Duration.zero)),
          isTrue);
    }
    expect(isReservedRemoteKey(_press(PhysicalKeyboardKey.mediaPlayPause)),
        isFalse);
  });
}
