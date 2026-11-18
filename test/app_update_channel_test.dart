import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/screens/settings/app_update_screen.dart';
import 'package:nox_iptv/services/app_update_service.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/widgets/tv_menu_tile.dart';

/// The update channel rows must behave like ordinary settings rows for a TV
/// remote: Down from Stable reaches Early builds, and Down again leaves the
/// section for the buttons below. A RadioGroup was tried here and reverted
/// because it maps Up/Down to intra-group selection (wrapping at the ends),
/// which trapped focus inside the two options so Download/Install below
/// could never be reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppUpdateService> openService() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final update = AppUpdateService(storage);
    // Skip the network check the screen runs in initState; traversal is
    // what this test exercises, not the update server.
    update.checked = true;
    return update;
  }

  Future<void> pumpScreen(
      WidgetTester tester, AppUpdateService update) async {
    PackageInfo.setMockInitialValues(
      appName: 'StreamSports',
      packageName: 'test',
      version: '0.2.63',
      buildNumber: '2556',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppUpdateService>.value(
          value: update,
          child: const AppUpdateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FocusNode channelNode(WidgetTester tester, int index) =>
      tester.widget<TvMenuTile>(find.byType(TvMenuTile).at(index)).focusNode!;

  testWidgets('arrow down walks out of the update channel rows',
      (tester) async {
    await pumpScreen(tester, await openService());

    final rows = find.byType(TvMenuTile);
    expect(rows, findsNWidgets(2));

    channelNode(tester, 0).requestFocus();
    await tester.pump();
    expect(channelNode(tester, 0).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(channelNode(tester, 1).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(channelNode(tester, 0).hasFocus, isFalse);
    expect(channelNode(tester, 1).hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}
