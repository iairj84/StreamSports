import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/playlist_profile.dart';
import '../services/app_preferences.dart';
import '../services/app_update_service.dart';
import '../services/epg_service.dart';
import '../services/phone_pairing_service.dart';
import '../services/phone_settings.dart';
import '../services/playlist_manager.dart';
import '../services/stalker_portal_service.dart';
import '../services/storage_service.dart';
import '../utils/tv_theme.dart';
import '../utils/xtream.dart';
import '../widgets/phone_pair_panel.dart';

/// Put up by first run when someone picks "Set up on my phone": one QR code
/// that the phone fills in with the playlist *and* the choices that otherwise
/// need a remote — theme, surface, clock, spoiler setting and update channel.
///
/// The panel it hosts is the same [PhonePairPanel] the other phone flows use;
/// only the [PairingKind.setup] payload and what this screen does with it are
/// new. Applying settings before adding the playlist means the playlist's
/// first load (and the guide warm-up it starts) already paints in the chosen
/// look instead of flashing the old theme and then switching.
class SetupFromPhoneScreen extends StatefulWidget {
  const SetupFromPhoneScreen({super.key});

  @override
  State<SetupFromPhoneScreen> createState() => _SetupFromPhoneScreenState();
}

class _SetupFromPhoneScreenState extends State<SetupFromPhoneScreen> {
  /// The panel's Wi-Fi/relay switch, kept here because this screen has no
  /// other focusable sibling for a remote to reach it through.
  final FocusNode _toggleFocus = FocusNode(debugLabel: 'setup-phone-toggle');

  bool _applying = false;

  @override
  void dispose() {
    _toggleFocus.dispose();
    super.dispose();
  }

  /// Applies the phone's choices, then adds the playlist. Failures keep the
  /// screen up so the code can be scanned again after the phone is corrected.
  Future<void> _apply(PairingResult result) async {
    if (_applying || !mounted) return;
    final prefs = context.read<AppPreferences>();
    final storage = context.read<StorageService>();
    final update = context.read<AppUpdateService>();
    final playlists = context.read<PlaylistManager>();
    final epg = context.read<EpgService>();
    // Captured before any await so the result path never needs the
    // BuildContext after an asynchronous gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _applying = true);

    void fail(String message) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      setState(() => _applying = false);
    }

    try {
      // The same writer the settings-only page uses: a setup payload is the
      // playlist plus whichever preferences the phone offered.
      await applyPhoneSettings(result.settings,
          prefs: prefs, storage: storage, update: update);

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final enteredEpg = result.epgUrl.trim();
      final name = result.name.isEmpty ? tr('My playlist') : result.name;
      final PlaylistProfile profile;
      if (result.mode == 'stalker') {
        // The same validation Add Playlist runs, so a typo in either field is
        // reported here instead of failing later during the first load.
        portalEndpoints(result.portalUrl);
        final mac = normalizePortalMac(result.portalMac);
        profile = PlaylistProfile(
          id: id,
          name: name,
          mode: 'stalker',
          portalUrl: result.portalUrl,
          portalMac: mac,
          portalUsername: result.portalUsername,
          portalPassword: result.portalPassword,
          epgUrl: result.includeLive ? enteredEpg : '',
          includeLive: result.includeLive,
          includeMovies: result.includeMovies,
          includeSeries: result.includeSeries,
          categoryLayout: 'provider',
          sortOrder: playlists.profiles.length,
          createdAt: DateTime.now(),
        );
      } else if (result.mode == 'xtream') {
        final server = XtreamHelper.normalizeServer(result.server);
        final derived = result.includeLive
            ? XtreamHelper.buildEpgUrl(
                server: server,
                username: result.username,
                password: result.password)
            : '';
        profile = PlaylistProfile(
          id: id,
          name: name,
          mode: 'xtream',
          xtreamServer: server,
          xtreamUsername: result.username,
          xtreamPassword: result.password,
          epgUrl: result.includeLive
              ? (enteredEpg.isNotEmpty ? enteredEpg : derived)
              : '',
          includeLive: result.includeLive,
          includeMovies: result.includeMovies,
          includeSeries: result.includeSeries,
          categoryLayout: 'provider',
          sortOrder: playlists.profiles.length,
          createdAt: DateTime.now(),
        );
      } else {
        profile = PlaylistProfile(
          id: id,
          name: name,
          mode: 'm3u',
          m3uUrl: result.m3uUrl,
          epgUrl: enteredEpg,
          categoryLayout: 'provider',
          sortOrder: playlists.profiles.length,
          createdAt: DateTime.now(),
        );
      }

      await playlists.addPlaylist(profile);
      await playlists.loadPlaylist(id);
      if (playlists.error != null) {
        // A failed first connect must not leave an empty profile behind.
        await playlists.removePlaylist(id);
        fail(tr(
            'The playlist could not be added. Check its details on your phone and scan again.'));
        return;
      }

      if (profile.isStalker &&
          profile.includeLive &&
          profile.allEpgUrls.isEmpty) {
        unawaited(epg.refreshPortal(id));
      }
      // Same non-blocking guide start as Add Playlist: the form is done, and
      // a slow XMLTV feed must not keep the viewer out of the app.
      final knownChannelIds = playlists.knownChannelIdsFor(id);
      final knownChannelNames = playlists.knownChannelNamesFor(id);
      for (final url in profile.allEpgUrls) {
        unawaited(epg.refresh(url,
            knownChannelIds: knownChannelIds,
            knownChannelNames: knownChannelNames,
            headers: profile.requestHeaders));
      }

      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(tr('Setup complete. Your playlist is loading.'))));
      navigator.popUntil((route) => route.isFirst);
    } on PortalException catch (e) {
      fail(e.message);
    } on FormatException catch (e) {
      fail(e.message);
    } catch (e) {
      debugPrint('Phone setup failed: ${e.runtimeType}');
      fail(tr('Setup could not be saved. Please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return withTvThemeIfNeeded(
      context,
      (context) => Scaffold(
        appBar: AppBar(title: Text(tr('Set up on my phone'))),
        body: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: PhonePairPanel(
                    kind: PairingKind.setup,
                    toggleFocusNode: _toggleFocus,
                    onResult: _apply,
                  ),
                ),
              ),
            ),
            if (_applying)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(tr('Setting up…')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
