import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import 'storage_service.dart';

/// User display names for channels, kept on top of whatever the provider
/// sends.
///
/// The provider's playlist is never rewritten: an override is stored per
/// playlist (`rawId` -> name) and stamped onto the loaded [Channel] objects,
/// so a playlist refresh, an EPG reload or a cache restore re-applies it
/// rather than losing it. Names are read by the guide, the Sports matcher,
/// the channel picker and the player, so "US: ESPN 2 HD" can be renamed once
/// to "ESPN2" and match from then on.
class ChannelRenames {
  ChannelRenames._();

  static StorageService? _storage;
  static Map<String, Map<String, String>>? _cache;

  /// Called once at startup, after the storage service exists.
  static void bind(StorageService storage) {
    _storage = storage;
    _cache = null;
  }

  static Map<String, Map<String, String>> _all() {
    final storage = _storage;
    if (storage == null) return const {};
    return _cache ??= {
      for (final playlist in storage.getPlaylists())
        playlist.id: storage.getChannelNames(playlist.id),
    };
  }

  static String? nameFor(String playlistId, String rawId) =>
      _all()[playlistId]?[rawId];

  static bool isRenamed(Channel channel) =>
      nameFor(channel.playlistId, channel.rawId) != null;

  /// Stamps every override onto [channels] and restores provider names whose
  /// override is gone. Safe to call repeatedly on the same objects.
  static void apply(Iterable<Channel> channels) {
    for (final channel in channels) {
      applyTo(channel, nameFor(channel.playlistId, channel.rawId));
    }
  }

  @visibleForTesting
  static void applyTo(Channel channel, String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      final original = channel.originalName;
      if (original != null) {
        channel.name = original;
        channel.originalName = null;
      }
      return;
    }
    if (channel.name == trimmed) return;
    channel.originalName ??= channel.name;
    channel.name = trimmed;
  }

  /// Saves a batch of display names at once — what the phone editor sends —
  /// with one storage write per playlist instead of one per channel. Empty
  /// names clear an override, like [rename]. Returns how many channels changed.
  static Future<int> renameMany(
      StorageService storage, Iterable<(Channel, String)> renames) async {
    bind(storage);
    final byPlaylist = <String, Map<String, String>>{};
    final changed = <Channel>[];
    for (final (channel, name) in renames) {
      final names = byPlaylist.putIfAbsent(channel.playlistId,
          () => {...storage.getChannelNames(channel.playlistId)});
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        if (names.remove(channel.rawId) == null) continue;
      } else {
        if (names[channel.rawId] == trimmed) continue;
        names[channel.rawId] = trimmed;
      }
      changed.add(channel);
    }
    if (changed.isEmpty) return 0;
    for (final entry in byPlaylist.entries) {
      await storage.setChannelNames(entry.key, entry.value);
    }
    _cache = null;
    for (final channel in changed) {
      applyTo(channel, nameFor(channel.playlistId, channel.rawId));
    }
    return changed.length;
  }

  /// Saves one channel's display name, or clears it with an empty [name].
  /// Returns true when something changed.
  static Future<bool> rename(
      StorageService storage, Channel channel, String? name) async {
    bind(storage);
    final names = {...storage.getChannelNames(channel.playlistId)};
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      if (names.remove(channel.rawId) == null) return false;
    } else {
      if (names[channel.rawId] == trimmed) return false;
      names[channel.rawId] = trimmed;
    }
    await storage.setChannelNames(channel.playlistId, names);
    _cache = null;
    applyTo(channel, names[channel.rawId]);
    return true;
  }
}
