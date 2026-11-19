import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/surface_style.dart';
import 'package:nox_iptv/screens/settings/theme_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/tv_theme.dart';

void main() {
  test('surface tokens keep Classic geometry and round Modern up', () {
    final classic = SurfaceTokens.forStyle(SurfaceStyle.classic);
    expect(classic.rowRadius, 3);
    expect(classic.blockRadius, 2);
    expect(classic.focusBorderWidth, 2.5);
    expect(classic.focusGlowBlur, 0);
    final modern = SurfaceTokens.forStyle(SurfaceStyle.modern);
    expect(modern.rowRadius, greaterThan(classic.rowRadius));
    expect(modern.blockRadius, greaterThan(classic.blockRadius));
    expect(modern.focusBorderWidth, lessThan(classic.focusBorderWidth));
    expect(modern.focusGlowBlur, greaterThan(0));
    expect(SurfaceTokens.fromId(SurfaceStyle.modern.name),
        SurfaceStyle.modern);
    expect(SurfaceTokens.fromId('anything-else'), SurfaceStyle.classic);
    expect(SurfaceTokens.fromId(null), SurfaceStyle.classic);
  });

  test('Stadium Night is a whole look, not a colour swap', () {
    final classic = SurfaceTokens.forStyle(SurfaceStyle.classic);
    final stadium = SurfaceTokens.forStyle(SurfaceStyle.stadium);
    expect(SurfaceTokens.fromId('stadium'), SurfaceStyle.stadium);
    expect(stadium.rounded, isTrue);
    expect(classic.rounded, isFalse);
    // Shape: pill surfaces well past Modern's rounding.
    expect(stadium.rowRadius,
        greaterThan(SurfaceTokens.forStyle(SurfaceStyle.modern).rowRadius));
    expect(stadium.blockRadius, greaterThan(6));
    // Focus language: ring plus halo instead of an accent fill.
    expect(stadium.focusRingOnly, isTrue);
    expect(classic.focusRingOnly, isFalse);
    expect(stadium.focusGlowBlur, greaterThan(14));
    // Type language: tracked caps, heavier titles, a dedicated score size.
    expect(stadium.uppercaseLabels, isTrue);
    expect(stadium.labelLetterSpacing, greaterThan(0));
    expect(stadium.titleWeight, FontWeight.w800);
    expect(classic.titleWeight, FontWeight.w600);
    expect(stadium.scoreSize, greaterThan(classic.scoreSize));
    expect(stadium.uppercasesStatus, isTrue);
    expect(classic.uppercasesStatus, isFalse);
    expect(stadium.uppercaseLabels && stadium.focusRingOnly &&
        stadium.uppercasesStatus, isTrue, reason: 'tokens combine into one look');
  });

  test('prefs default to Classic and persist the choice', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    expect(prefs.surfaceStyle, SurfaceStyle.classic);
    await prefs.setSurfaceStyle(SurfaceStyle.modern);
    expect(prefs.surfaceStyle, SurfaceStyle.modern);
    final reread = AppPreferences(storage);
    await reread.init();
    expect(reread.surfaceStyle, SurfaceStyle.modern);
    prefs.dispose();
    reread.dispose();
  });

  testWidgets('theme screen surface section switches the look',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider.value(value: prefs),
        ],
        child: MaterialApp(
            theme: buildAppTheme(prefs.palette),
            home: const ThemeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Surface'), findsOneWidget);
    await tester.tap(find.text('Modern'));
    await tester.pumpAndSettle();
    expect(prefs.surfaceStyle, SurfaceStyle.modern);
    await tester.ensureVisible(find.text('Stadium Night'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stadium Night'));
    await tester.pumpAndSettle();
    expect(prefs.surfaceStyle, SurfaceStyle.stadium);
    expect(tester.takeException(), isNull);
  });
}
