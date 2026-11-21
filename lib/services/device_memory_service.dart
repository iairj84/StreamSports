import 'package:flutter/services.dart';

/// Real device memory info from Android's ActivityManager — see
/// MainActivity.kt's doc comment for why this needs a small native call
/// (Flutter has no built-in way to ask "how much RAM does this device
/// have").
class DeviceMemoryInfo {
  const DeviceMemoryInfo(
      {required this.totalMemBytes, required this.isLowRamDevice});

  final int totalMemBytes;

  /// Android's own official "is this a memory-constrained device" flag
  /// (`ActivityManager.isLowRamDevice()`) — accounts for OEM-specific
  /// thresholds better than a flat GB cutoff would on its own.
  final bool isLowRamDevice;

  double get totalMemGB => totalMemBytes / (1024 * 1024 * 1024);
}

class DeviceMemoryService {
  static const _channel = MethodChannel('com.nox.nox_iptv/device_memory');

  /// Null on any failure (non-Android platform, channel not implemented,
  /// unexpected native exception) — callers must fall back to a safe,
  /// conservative default rather than guess or crash.
  static Future<DeviceMemoryInfo?> getMemoryInfo() async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getMemoryInfo')
          .timeout(const Duration(seconds: 2));
      if (result == null) return null;
      return DeviceMemoryInfo(
        totalMemBytes: result['totalMemBytes'] as int,
        isLowRamDevice: result['isLowRamDevice'] as bool,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Whether this device is a television — asked natively because screen
/// size can't answer it. See MainActivity.kt: the "auto" layout mode used
/// to compare MediaQuery's width against a fixed logical-pixel threshold,
/// and a 1080p TV at 2x density reports 960dp, so every TV box and Fire
/// Stick fell under it and got the phone layout on first launch.
class DeviceTypeService {
  static const _channel = MethodChannel('com.nox.nox_iptv/device_type');

  /// False on any failure, so a device that can't answer falls back to the
  /// previous size-based behaviour rather than forcing a TV layout onto a
  /// phone.
  static Future<bool> isTelevision() async {
    try {
      return await _channel
              .invokeMethod<bool>('isTelevision')
              .timeout(const Duration(seconds: 2)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// What another device lists this one as. [unnamedDevice] is the last
  /// resort: a row that reads like the device in your hand is the confusion
  /// this avoids, so no caller has to invent a name of its own.
  static const String unnamedDevice = 'Android device';

  /// Android's own device name when it has one, else manufacturer and model,
  /// trimmed and capped to one list row. Never null, so nothing downstream has
  /// to decide what to show.
  static Future<String> transferName() async {
    try {
      final name = (await _channel
              .invokeMethod<String>('deviceName')
              .timeout(const Duration(seconds: 2)))
          ?.trim();
      if (name == null || name.isEmpty) return unnamedDevice;
      return name.length > 40 ? name.substring(0, 40) : name;
    } catch (_) {
      return unnamedDevice;
    }
  }
}

/// Live channel logos are small; poster-sized caches compete with the decoder.
int imageCacheBudgetBytes(DeviceMemoryInfo? info) {
  if (info == null || info.isLowRamDevice || info.totalMemGB < 3) {
    return 32 << 20;
  }
  return 64 << 20;
}
