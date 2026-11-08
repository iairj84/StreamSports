import '../../widgets/iptv_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../services/app_preferences.dart';
import '../../services/additional_licenses.dart';
import '../../utils/tv_theme.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/tv_menu_tile.dart';
import '../../l10n/l10n.dart';

import 'general_settings_screen.dart';
import 'remote_control_screen.dart';
import 'app_update_screen.dart';
import 'device_transfer_screen.dart';
import 'playlist_manager_screen.dart';
import 'theme_screen.dart';

import 'library_settings_screen.dart';
import 'launcher_icon_screen.dart';

enum SettingsAction {
  live,
  sports,
  search,
  multiview,
  refresh,
  movies,
  shows,
  disableAndExit
}

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key, this.includeTools = false});
  final bool includeTools;

  void _returnAction(BuildContext context, SettingsAction action) {
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<AppPreferences>();
    Widget link(IconData icon, String title, String subtitle, Widget page) =>
        TvMenuTile(
            icon: icon,
            title: tr(title),
            subtitle: tr(subtitle),
            onTap: () => Navigator.of(context)
                .push(SettingsRoute(builder: (_) => page)));
    Widget action(IconData icon, String title, String subtitle,
            SettingsAction value) =>
        TvMenuTile(
            icon: icon,
            title: tr(title),
            subtitle: tr(subtitle),
            onTap: () => _returnAction(context, value));
    return withTvThemeIfNeeded(
        context,
        (context) => SettingsScaffold(
              title: tr('Settings'),
              bottomNavigationBar: includeTools &&
                      !prefs.isTelevision &&
                      MediaQuery.sizeOf(context).width < 600
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: IptvBottomBar(
                          selected: 'settings',
                          onSelect: (value) {
                            if (value == 'movies' || value == 'series') {
                              _returnAction(
                                  context,
                                  value == 'movies'
                                      ? SettingsAction.movies
                                      : SettingsAction.shows);
                            }
                            if (value == 'live') {
                              _returnAction(context, SettingsAction.live);
                            }
                            if (value == 'sports') {
                              _returnAction(context, SettingsAction.sports);
                            }
                          }))
                  : null,
              body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    SettingsSection(title: tr('Your TV'), children: [
                      link(
                          Icons.playlist_play,
                          'Playlists & guide',
                          'Channels, categories and program listings',
                          const PlaylistManagerScreen()),
                    ]),
                    SettingsSection(title: tr('Movies & series'), children: [
                      link(
                          Icons.video_library_outlined,
                          'Library preferences',
                          'Tabs, categories and on-demand browsing',
                          const LibrarySettingsScreen()),
                    ]),
                    SettingsSection(title: tr('Make it yours'), children: [
                      link(
                          Icons.tune,
                          'Playback & preferences',
                          'Startup, language and history',
                          const GeneralSettingsScreen()),
                      link(
                          Icons.display_settings_outlined,
                          'Themes',
                          'Six palettes · true black to light',
                          const ThemeScreen()),
                      link(
                          Icons.settings_remote,
                          'Remote control',
                          'What each button does, and remapping the spare ones',
                          const RemoteControlScreen()),
                    ]),
                    if (includeTools && !prefs.hideMultiview)
                      SettingsSection(title: tr('Viewing tools'), children: [
                        action(
                            Icons.grid_view,
                            'Multiview',
                            'Watch live channels side by side',
                            SettingsAction.multiview),
                      ]),
                    SettingsSection(title: tr('Devices & app'), children: [
                      link(
                          Icons.image_outlined,
                          'Launcher icon',
                          'Save the transparent logo for Projectivy and other launchers',
                          const LauncherIconScreen()),
                      link(
                          Icons.sync_alt,
                          'Transfer to another device',
                          'Copy playlists, settings and sports picks over Wi-Fi',
                          const DeviceTransferScreen()),
                      link(
                          Icons.info_outline,
                          'About StreamSports',
                          'Version, credits and open-source licences',
                          const AppInfoScreen()),
                      link(
                          Icons.system_update_alt,
                          'App updates',
                          'Download and install a newer build',
                          const AppUpdateScreen()),
                      if (includeTools)
                        action(
                            Icons.power_settings_new,
                            'Disable and exit',
                            'Disable playlists and release this login',
                            SettingsAction.disableAndExit),
                    ]),
                  ]),
            ));
  }
}

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});
  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  late final _version = PackageInfo.fromPlatform();

  @override
  void initState() {
    super.initState();
    registerAdditionalLicenses();
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
      title: tr('About StreamSports'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SettingsSection(title: 'StreamSports', children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        tr('Live TV, sports, movies and series from your own playlists.'),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    FutureBuilder<PackageInfo>(
                        future: _version,
                        builder: (context, snapshot) => Text(
                            snapshot.hasData
                                ? 'Version ${snapshot.data!.version} · ${snapshot.data!.buildNumber}'
                                : tr('Version —'),
                            style: Theme.of(context).textTheme.bodySmall)),
                  ])),
          TvMenuTile(
              icon: Icons.code,
              title: tr('Open-source licences'),
              onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'StreamSports',
                  applicationLegalese:
                      'Based on VesperTV by NoXqc and contributors. GPL-3.0.')),
        ]),
        SettingsSection(title: tr('Credits'), children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  tr('Based on VesperTV by NoXqc and contributors. Modified and distributed under GPL-3.0, without warranty. Channel content comes from your playlists. Program listings and sports coverage depend on the available sources.'),
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ]));
}
