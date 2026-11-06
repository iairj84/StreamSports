import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

/// Something a remapped remote button can do while Live TV is on screen.
enum RemoteAction {
  live('live', 'Live TV'),
  sports('sports', 'Sports'),
  search('search', 'Search'),
  multiview('multiview', 'Multiview'),
  movies('movies', 'Movies'),
  shows('shows', 'TV Shows'),
  settings('settings', 'Settings');

  const RemoteAction(this.id, this.label);

  /// Stable id for the saved map — never reuse one.
  final String id;

  /// English label; screens pass it through `tr()`.
  final String label;

  static RemoteAction? byId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// One button the viewer chose, plus the words to show for it. The label is
/// captured on the device that pressed the button: a TV remote sends keys
/// Flutter has no name for (coloured buttons especially), and a bare number
/// would read as gibberish in Settings.
class RemoteBinding {
  const RemoteBinding(this.action, this.label);

  final RemoteAction action;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is RemoteBinding && other.action == action && other.label == label;

  @override
  int get hashCode => Object.hash(action, label);
}

/// Remote button remapping (Settings > Remote control).
///
/// Keys are stored by [PhysicalKeyboardKey.usbHidUsage], not the logical key: the
/// logical key follows the platform's keyboard layout, while the physical id
/// is the remote's own button. Nothing is bound by default, so an untouched
/// install behaves exactly as before — the handler in `TvHomeScreen` only
/// consumes keys that are in this map.
class RemoteControls extends ChangeNotifier {
  RemoteControls._();

  /// A private instance for tests; screens use [instance].
  @visibleForTesting
  RemoteControls.test();

  static final RemoteControls instance = RemoteControls._();

  StorageService? _storage;
  bool _attached = false;

  final Map<int, RemoteBinding> _bindings = {};

  /// Bound buttons, by the pressed key's USB HID usage (its physical id).
  Map<int, RemoteBinding> get bindings => Map.unmodifiable(_bindings);

  bool get isEmpty => _bindings.isEmpty;

  RemoteBinding? bindingFor(int physicalKeyUsage) => _bindings[physicalKeyUsage];

  RemoteBinding? bindingForAction(RemoteAction action) {
    for (final binding in _bindings.values) {
      if (binding.action == action) return binding;
    }
    return null;
  }

  /// Loads the saved map once. Later calls are no-ops, so any screen can call
  /// it before reading [bindings].
  void attach(StorageService storage) {
    if (_attached) return;
    _attached = true;
    _storage = storage;
    _replaceFromJson(storage.getRemoteControlBindings());
  }

  /// Binds [physicalKeyId] to [action]. A button does one thing and an action
  /// has one button, so both stale entries are dropped.
  void bind(int physicalKeyId, RemoteAction action, {required String label}) {
    final existing = _bindings[physicalKeyId];
    if (existing != null && existing.action == action && existing.label == label) {
      return;
    }
    _bindings.removeWhere(
        (key, binding) => key == physicalKeyId || binding.action == action);
    _bindings[physicalKeyId] = RemoteBinding(action, label);
    _save();
    notifyListeners();
  }

  void unbind(RemoteAction action) {
    final before = _bindings.length;
    _bindings.removeWhere((_, binding) => binding.action == action);
    if (_bindings.length == before) return;
    _save();
    notifyListeners();
  }

  void reset() {
    if (_bindings.isEmpty) return;
    _bindings.clear();
    _save();
    notifyListeners();
  }

  /// The action [event] triggers, or null when the button is not remapped.
  /// Only presses count, so holding a button doesn't fire it twice.
  RemoteAction? actionFor(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    return _bindings[event.physicalKey.usbHidUsage]?.action;
  }

  String toJson() => jsonEncode({
        for (final entry in _bindings.entries)
          '${entry.key}': {
            'action': entry.value.action.id,
            'label': entry.value.label,
          }
      });

  /// For tests, and for a fresh load from storage.
  @visibleForTesting
  void loadFrom(String? raw) => _replaceFromJson(raw);

  void _save() {
    _storage?.setRemoteControlBindings(_bindings.isEmpty ? null : toJson());
  }

  void _replaceFromJson(String? raw) {
    _bindings.clear();
    if (raw == null || raw.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    decoded.forEach((key, value) {
      final id = int.tryParse('$key');
      if (id == null || value is! Map) return;
      final action = RemoteAction.byId('${value['action']}');
      if (action == null) return;
      final label = '${value['label'] ?? ''}'.trim();
      _bindings[id] = RemoteBinding(action, label.isEmpty ? action.label : label);
    });
  }
}

/// TV-remote buttons Flutter already knows, spelled the way a viewer reads
/// them. Anything else falls back to the key's own name in [remoteKeyLabel].
final Map<int, String> _knownKeyNames = {
  for (final entry in <PhysicalKeyboardKey, String>{
    PhysicalKeyboardKey.mediaPlayPause: 'Play / pause',
    PhysicalKeyboardKey.mediaPlay: 'Play',
    PhysicalKeyboardKey.mediaPause: 'Pause',
    PhysicalKeyboardKey.mediaStop: 'Stop',
    PhysicalKeyboardKey.mediaTrackNext: 'Next',
    PhysicalKeyboardKey.mediaTrackPrevious: 'Previous',
    PhysicalKeyboardKey.mediaFastForward: 'Fast forward',
    PhysicalKeyboardKey.mediaRewind: 'Rewind',
    PhysicalKeyboardKey.mediaRecord: 'Record',
    PhysicalKeyboardKey.browserSearch: 'Search',
    PhysicalKeyboardKey.browserHome: 'Home',
    PhysicalKeyboardKey.launchMail: 'Mail',
    PhysicalKeyboardKey.f1: 'F1',
    PhysicalKeyboardKey.f2: 'F2',
    PhysicalKeyboardKey.f3: 'F3',
    PhysicalKeyboardKey.f4: 'F4',
  }.entries)
    entry.key.usbHidUsage: entry.value,
};

/// What to show for the button that was just pressed.
String remoteKeyLabel(KeyEvent event) {
  final keyId = event.physicalKey.usbHidUsage;
  final known = _knownKeyNames[keyId];
  if (known != null) return known;
  final debug = event.physicalKey.debugName;
  if (debug != null && debug.isNotEmpty) {
    // 'keyCodeMediaPlayPause' -> 'Media Play Pause'.
    final name = debug
        .replaceFirst('keyCode', '')
        .replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match[0]}')
        .trim();
    if (name.isNotEmpty) return name;
  }
  final logical = event.logicalKey.keyLabel;
  if (logical.isNotEmpty) return logical;
  return 'Button 0x${keyId.toRadixString(16).toUpperCase()}';
}

/// Buttons the app's own navigation depends on, so they are never taken for a
/// remap — losing Down or Back on a TV remote would strand the viewer.
bool isReservedRemoteKey(KeyEvent event) {
  final key = event.logicalKey;
  return key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.tab ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.gameButtonA;
}
