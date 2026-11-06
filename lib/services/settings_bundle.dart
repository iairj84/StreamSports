import 'dart:convert';

import '../utils/constants.dart';
import 'storage_service.dart';

/// What a device transfer carries. A transfer replaces the receiving device's
/// copy of every section it sends — never merges — so the two devices agree.
enum TransferSection { playlists, settings, sports, lists }

extension TransferSectionLabel on TransferSection {
  String get label => switch (this) {
        TransferSection.playlists => 'Playlists and guide sources',
        TransferSection.settings => 'Settings, theme and startup',
        TransferSection.sports => 'Sports picks and followed teams',
        TransferSection.lists =>
          'Favorites, hidden channels, group order and channel links',
      };
}

/// Keys that describe *this* device, a one-time migration guard or a disposable
/// cache. They are never copied: a new device must not inherit a stale update
/// check, someone else's playback position, or a window geometry.
const Set<String> _deviceOnlyKeys = {
  AppConstants.keyEpgCache,
  AppConstants.keyEpgLastUpdated,
  AppConstants.keyLastChannelId,
  AppConstants.keyActiveViewerId,
  AppConstants.keyCloudTransfer,
  AppConstants.keyLastFullSyncAt,
  AppConstants.keyFavoritesDbReconciled,
  AppConstants.keyMigratedToMultiPlaylist,
  AppConstants.keyLayoutMode,
  AppConstants.keyWindowsWindowed,
  AppConstants.keyWindowsBounds,
  AppConstants.keyVideoFill,
  AppConstants.keyLastUpdateCheck,
  AppConstants.keySkippedUpdateVersion,
  AppConstants.keyRecentSearches,
  AppConstants.keyArchiveHistory,
  AppConstants.keyArchiveRecentSearches,
  AppConstants.keySeriesSubtitles,
  AppConstants.keyWhatsNewTmdbLastRefreshed,
  AppConstants.keyWhatsNewVodIds,
  AppConstants.keyWhatsNewSeriesIds,
  AppConstants.keyPinFailCount,
  AppConstants.keyPinLockedUntil,
};

/// Prefixes for per-playlist timestamps, resume positions and migration guards.
const List<String> _deviceOnlyPrefixes = [
  'nox_last_position_',
  'nox_last_duration_',
  'nox_last_full_sync_at_',
  'nox_last_channel_id_',
  'iptv_classic_layout',
  'sports_coverage_',
];

/// Legacy single-playlist keys, still read during migration; part of the
/// playlist section so an old install can be copied as-is.
const Set<String> _playlistKeys = {
  AppConstants.keyPlaylists,
  AppConstants.keyM3uUrl,
  AppConstants.keyEpgUrl,
  AppConstants.keyPlaylistMode,
  AppConstants.keyPlaylistEnabled,
  AppConstants.keyXtreamServer,
  AppConstants.keyXtreamUsername,
  AppConstants.keyXtreamPassword,
};

/// Per-viewer curation: what the viewer chose, not how the device behaves.
const Set<String> _listKeys = {
  AppConstants.keyFavorites,
  AppConstants.keyFavoriteSeries,
  AppConstants.keyHiddenGroups,
  AppConstants.keyShownGroups,
  AppConstants.keyHiddenChannels,
  AppConstants.keyEpgIdOverrides,
  AppConstants.keyChannelLinks,
  AppConstants.keyAutoPairedChannelLinks,
  AppConstants.keyAutoPairedEpgOverrides,
  AppConstants.keyFavoritedGroups,
  AppConstants.keyGroupOrder,
};

/// Preference keys may be per-viewer (`…__vp_<id>`); classify by the base key
/// so a transfer carries every viewer, not just the active one.
String transferBaseKey(String key) {
  final index = key.indexOf(AppConstants.viewerKeySuffix);
  return index < 0 ? key : key.substring(0, index);
}

bool isDeviceOnlyPreference(String key) {
  if (_deviceOnlyKeys.contains(key)) return true;
  return _deviceOnlyPrefixes.any(key.startsWith);
}

TransferSection? transferSectionOf(String key) {
  final base = transferBaseKey(key);
  if (isDeviceOnlyPreference(base) || isDeviceOnlyPreference(key)) return null;
  if (_playlistKeys.contains(base)) return TransferSection.playlists;
  if (base.startsWith('vesper_sports_')) return TransferSection.sports;
  if (_listKeys.contains(base)) return TransferSection.lists;
  return TransferSection.settings;
}

/// One device's copy of the configuration, ready to be encrypted and sent.
class SettingsBundle {
  const SettingsBundle({
    required this.values,
    required this.createdAt,
    required this.appVersion,
  });

  /// Preference key → JSON value, already filtered to the sent sections.
  final Map<String, Object?> values;
  final DateTime createdAt;
  final String appVersion;

  /// Refuse a payload that is not ours, is from a newer format, or is large
  /// enough to be an attack rather than a settings file.
  static const int format = 1;
  static const int maxBytes = 512 * 1024;

  Map<String, Object?> toJson() => {
        'format': format,
        'app': appVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'values': values,
      };

  String encode() => jsonEncode(toJson());

  int get byteLength => utf8.encode(encode()).length;

  /// Null when [json] is not a bundle this build understands.
  static SettingsBundle? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['format'] != format) return null;
    final raw = json['values'];
    if (raw is! Map) return null;
    final values = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty || key.length > 200) return null;
      final value = entry.value;
      final valid = value is String ||
          value is bool ||
          value is int ||
          value is double ||
          (value is List && value.every((v) => v is String));
      if (!valid) return null;
      values[key] = value;
    }
    return SettingsBundle(
      values: values,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      appVersion: '${json['app'] ?? ''}',
    );
  }

  /// Everything this device would send, limited to [sections].
  static SettingsBundle capture(
    StorageService storage, {
    required Set<TransferSection> sections,
    String appVersion = '',
  }) {
    final values = <String, Object?>{};
    for (final entry in storage.rawPreferences().entries) {
      final section = transferSectionOf(entry.key);
      if (section == null || !sections.contains(section)) continue;
      values[entry.key] = entry.value;
    }
    return SettingsBundle(
      values: values,
      createdAt: DateTime.now(),
      appVersion: appVersion,
    );
  }

  Set<TransferSection> get sections {
    final result = <TransferSection>{};
    for (final key in values.keys) {
      final section = transferSectionOf(key);
      if (section != null) result.add(section);
    }
    return result;
  }

  /// Replace this device's copy of the carried sections. Device-only keys and
  /// every section this bundle did not carry are left exactly as they are.
  Future<TransferReport> applyTo(StorageService storage) async {
    final touched = <TransferSection>{};
    final remove = <String>[];
    for (final key in storage.rawPreferences().keys) {
      final section = transferSectionOf(key);
      if (section == null || !sections.contains(section)) continue;
      remove.add(key);
      touched.add(section);
    }
    await storage.replaceRawPreferences(values, remove: remove);
    return TransferReport(
      values: values.length,
      removed: remove.length,
      sections: touched,
    );
  }
}

/// What a receiving device reports back after applying a bundle.
class TransferReport {
  const TransferReport(
      {required this.values, required this.removed, required this.sections});

  final int values;
  final int removed;
  final Set<TransferSection> sections;

  Map<String, Object?> toJson() => {
        'values': values,
        'removed': removed,
        'sections': [for (final s in sections) s.name],
      };
}
