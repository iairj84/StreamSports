import 'dart:async';

import '../models/surface_style.dart';
import '../utils/constants.dart';
import '../utils/playback_buffer.dart';
import '../widgets/live_resume_hint.dart';
import 'app_preferences.dart';
import 'app_update_service.dart';
import 'live_buffer.dart';
import 'storage_service.dart';

/// Every preference a phone page may change, in the vocabulary the query
/// string and the payload both use. Anything outside this list is dropped in
/// `PairingResult.fromJson`, so a stale or hand-edited page cannot write an
/// arbitrary setting.
const List<String> phoneSettingKeys = [
  'palette',
  'surface',
  'clock24',
  'language',
  'buffer',
  'livebuffer',
  'startup',
  'updateplaylists',
  'pip',
  'resumepill',
  'moviestab',
  'seriestab',
  'multiview',
  'scores',
  'update',
];

/// The languages Settings > Playback & preferences offers; a phone page cannot
/// introduce one this build has no dictionary for.
const List<String> phoneLanguageCodes = ['auto', 'en', 'fr', 'es', 'it'];

String _flag(bool value) => value ? '1' : '0';

/// This device's current values for [phoneSettingKeys], keyed the same way the
/// phone will send them back.
///
/// Both phone forms start from this rather than from the page's own defaults:
/// a settings page that opened on "unchecked" would quietly switch things off
/// the moment someone sent it having changed one row.
Map<String, String> phoneSettingsSnapshot({
  required AppPreferences prefs,
  required StorageService storage,
}) =>
    {
      'palette': prefs.palette.id,
      'surface': prefs.surfaceStyle.name,
      'clock24': _flag(prefs.use24h),
      'language': prefs.language,
      'buffer': storage.getPlaybackBuffer(),
      'livebuffer': '${storage.getLiveBufferMs()}',
      'startup': storage.getResumeLastChannelAtStartup()
          ? 'full'
          : storage.getResumeLastChannelInGuide()
              ? 'preview'
              : 'off',
      'updateplaylists': _flag(storage.getUpdatePlaylistsAtStartup()),
      'pip': _flag(storage.getPictureInPictureOnHome()),
      'resumepill': _flag(storage.getShowResumePill()),
      'moviestab': _flag(!prefs.hideMovies),
      'seriestab': _flag(!prefs.hideShows),
      'multiview': _flag(!prefs.hideMultiview),
      'scores': _flag(storage.getSportsHideScores()),
      'update': storage.getUpdateChannel(),
    };

/// Applies what the phone sent, one key at a time: a setup payload carries the
/// five preferences first run asks for, a settings payload carries whatever the
/// viewer changed, and either way a key that is absent is left alone.
///
/// Unrecognised values are ignored rather than rejected — a newer phone page
/// that offers a buffering preset or a palette this build does not know must
/// not cost the viewer the rest of the form.
Future<void> applyPhoneSettings(
  Map<String, String> settings, {
  required AppPreferences prefs,
  required StorageService storage,
  AppUpdateService? update,
}) async {
  bool? flag(String key) => switch (settings[key]) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  // Look first: the rows below are painted in it, and a viewer who scanned to
  // change the theme sees the change while the rest is still being written.
  final paletteId = settings['palette'];
  if (paletteId != null) {
    for (final palette in AppConstants.cyberpunkPalettes) {
      if (palette.id != paletteId) continue;
      await prefs.setPalette(palette);
      break;
    }
  }
  final surfaceId = settings['surface'];
  if (surfaceId != null) {
    await prefs.setSurfaceStyle(SurfaceTokens.fromId(surfaceId));
  }

  final clock24 = flag('clock24');
  if (clock24 != null) prefs.setUse24h(clock24);

  final language = settings['language'];
  if (language != null && phoneLanguageCodes.contains(language)) {
    await prefs.setLanguage(language);
  }

  final buffer = settings['buffer'];
  if (buffer != null && playbackBufferPresetIds.contains(buffer)) {
    await storage.setPlaybackBuffer(buffer);
    applyPlaybackBufferPreset(buffer);
  }

  final liveMs = int.tryParse(settings['livebuffer'] ?? '');
  if (liveMs != null && liveBufferChoices.any((choice) => choice.$1 == liveMs)) {
    await storage.setLiveBufferMs(liveMs);
    // Forwarded to the native player for its next stream. Not awaited: the
    // phone is waiting for its confirmation, and a build without the native
    // port must not hold it there — the stored value is what the next launch
    // reads anyway.
    unawaited(LiveBuffer.setDefault(liveMs));
  }

  final startup = settings['startup'];
  if (startup == 'full' || startup == 'preview' || startup == 'off') {
    await storage.setResumeLastChannelAtStartup(startup == 'full');
    await storage.setResumeLastChannelInGuide(startup == 'preview');
  }

  final updatePlaylists = flag('updateplaylists');
  if (updatePlaylists != null) {
    await storage.setUpdatePlaylistsAtStartup(updatePlaylists);
  }

  final pip = flag('pip');
  if (pip != null) await storage.setPictureInPictureOnHome(pip);

  final resumePill = flag('resumepill');
  if (resumePill != null) {
    LiveResumeHint.pillEnabled.value = resumePill;
    await storage.setShowResumePill(resumePill);
  }

  final moviesTab = flag('moviestab');
  if (moviesTab != null) prefs.setHideMovies(!moviesTab);

  final seriesTab = flag('seriestab');
  if (seriesTab != null) prefs.setHideShows(!seriesTab);

  final multiview = flag('multiview');
  if (multiview != null) prefs.setHideMultiview(!multiview);

  final scores = flag('scores');
  if (scores != null) await storage.setSportsHideScores(scores);

  final channel = settings['update'];
  if (channel != null) {
    final next = channel == AppConstants.updateChannelEarly
        ? AppConstants.updateChannelEarly
        : AppConstants.updateChannelStable;
    // Recorded without asking the release feed: the phone is waiting for the
    // TV to accept its form, and a slow network must not hold that up.
    if (update != null) {
      await update.setChannelLocally(next);
    } else {
      await storage.setUpdateChannel(next);
    }
  }
}
