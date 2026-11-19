import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/app_preferences.dart';
import '../../services/app_update_service.dart';
import '../../services/phone_pairing_service.dart';
import '../../services/phone_settings.dart';
import '../../services/playback_service.dart';
import '../../services/storage_service.dart';
import '../../utils/tv_theme.dart';
import '../../widgets/phone_pair_panel.dart';

/// Settings > Settings from phone: the same QR panel the playlist and setup
/// flows use, with a [PairingKind.settings] page behind it.
///
/// The first-run code asks for a provider login because that is what first run
/// needs; changing the clock or the live buffer later should not. Nothing on
/// this screen touches [PlaylistManager], so a device with no playlist — or one
/// whose playlists are broken — can still change how it behaves.
class SettingsFromPhoneScreen extends StatefulWidget {
  const SettingsFromPhoneScreen({super.key});

  @override
  State<SettingsFromPhoneScreen> createState() =>
      _SettingsFromPhoneScreenState();
}

class _SettingsFromPhoneScreenState extends State<SettingsFromPhoneScreen> {
  /// The panel's Wi-Fi/relay switch, kept here because this screen has no
  /// other focusable sibling for a remote to reach it through.
  final FocusNode _toggleFocus = FocusNode(debugLabel: 'settings-phone-toggle');

  bool _applying = false;

  @override
  void dispose() {
    _toggleFocus.dispose();
    super.dispose();
  }

  Future<void> _apply(PairingResult result) async {
    if (_applying || !mounted) return;
    final prefs = context.read<AppPreferences>();
    final storage = context.read<StorageService>();
    final update = context.read<AppUpdateService?>();
    final playback = context.read<PlaybackService?>();
    // Captured before the awaits below so the result path never needs the
    // BuildContext after an asynchronous gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _applying = true);
    try {
      await applyPhoneSettings(result.settings,
          prefs: prefs, storage: storage, update: update);
      // The switch also drives the native side, which is not a stored value.
      final pip = result.settings['pip'];
      if (pip != null) {
        playback?.pictureInPicture.setAutoEnterOnLeave(pip == 'true');
      }
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(tr('Settings saved on your TV.'))));
      // A language change remounts the UI from home (see
      // GeneralSettingsScreen), so it cannot leave this route on top of the
      // old strings; every other change just returns to the screen that
      // opened the code.
      if (result.settings.containsKey('language')) {
        navigator.popUntil((route) => route.isFirst);
      } else {
        navigator.pop();
      }
    } catch (e) {
      debugPrint('Phone settings failed: ${e.runtimeType}');
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content:
                Text(tr('The settings could not be saved. Try again.'))));
      setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return withTvThemeIfNeeded(
      context,
      (context) => Scaffold(
        appBar: AppBar(title: Text(tr('Settings from phone'))),
        body: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: PhonePairPanel(
                    kind: PairingKind.settings,
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
                        Text(tr('Saving settings…')),
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
