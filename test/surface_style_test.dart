import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/surface_style.dart';
import 'package:nox_iptv/screens/settings/theme_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/widgets/sports_fixture_row.dart';
import 'package:nox_iptv/utils/constants.dart';
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

  test('theme-level surfaces follow the look, Classic and Modern do not', () {
    final palette = AppConstants.cyberpunkPalettes.first;
    double radiusOf(ShapeBorder? shape) =>
        ((shape as RoundedRectangleBorder).borderRadius as BorderRadius)
            .topLeft
            .x;
    final classic = buildAppTheme(palette);
    final modern = buildAppTheme(palette, surfaceStyle: SurfaceStyle.modern);
    final stadium =
        buildAppTheme(palette, surfaceStyle: SurfaceStyle.stadium);
    // Everything that used to be hardcoded keeps its exact number.
    expect(radiusOf(classic.dialogTheme.shape), 12);
    expect(radiusOf(classic.cardTheme.shape), 10);
    expect(radiusOf(classic.chipTheme.shape), 8);
    expect(radiusOf(modern.dialogTheme.shape), 12);
    expect(radiusOf(modern.chipTheme.shape), 8);
    expect(classic.dialogTheme.titleTextStyle, isNull);
    expect(modern.dialogTheme.titleTextStyle, isNull);
    // Stadium Night reaches dialogs, cards, chips, menus and inputs from the
    // token layer alone, so no screen has to re-style itself.
    expect(radiusOf(stadium.dialogTheme.shape), 22);
    expect(radiusOf(stadium.cardTheme.shape), 16);
    expect(radiusOf(stadium.chipTheme.shape), 18);
    expect(radiusOf(stadium.popupMenuTheme.shape), 18);
    expect(stadium.dialogTheme.titleTextStyle?.fontWeight, FontWeight.w800);
    final input = stadium.inputDecorationTheme.enabledBorder;
    expect((input as OutlineInputBorder).borderRadius.topLeft.x, 14);
  });

  testWidgets('Stadium Night titles and scores survive the tightest layout',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setSurfaceStyleId(SurfaceStyle.stadium.name);
    final prefs = AppPreferences(storage);
    await prefs.init();
    addTearDown(prefs.dispose);
    expect(prefs.surfaceStyle, SurfaceStyle.stadium);
    // The tightest of the four layout sizes: 320 logical px wide.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = SportsGame(
        id: 'nfl-game',
        league: sportsLeagueById('nfl')!,
        start: DateTime(2026, 11, 10, 19),
        state: GameState.live,
        statusText: '3rd 04:12',
        home: const SportsTeam(
            id: 'ne',
            name: 'New England Patriots',
            shortName: 'Patriots',
            abbreviation: 'NE',
            score: '114'),
        away: const SportsTeam(
            id: 'buf',
            name: 'Buffalo Bills',
            shortName: 'Bills',
            abbreviation: 'BUF',
            score: '110'),
        situation: const SportsSituation(
            text: '2nd & 7 at NE 32', possessionTeamId: 'ne'));
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider<AppPreferences>.value(value: prefs),
        ],
        child: MaterialApp(
            theme: buildAppTheme(prefs.palette,
                surfaceStyle: prefs.surfaceStyle),
            home: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 312,
                        height: 76,
                        child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: SportsFixtureRow(
                                game: game,
                                time: '8:15 PM',
                                hideScores: false,
                                use24h: false))))))));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'a heavier title or 19px score must not overflow the card');
    // The row really is wearing the look, not just the palette.
    final teamText = tester.widget<Text>(find.text('New England Patriots'));
    expect(teamText.style?.fontWeight, FontWeight.w800);
    final scoreText = tester.widget<Text>(find.text('114'));
    expect(scoreText.style?.fontSize, 19);
    // Status words take the same tracked-caps treatment as headings.
    final live = tester.widget<Text>(find.text('LIVE'));
    expect(live.style?.letterSpacing, .7);
    expect(live.style?.fontWeight, FontWeight.w600);
  });

  test('every legacy radius maps into the look, never touching Classic or Modern',
      () {
    const legacy = <double>[1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20];
    for (final style in [SurfaceStyle.classic, SurfaceStyle.modern]) {
      final tokens = SurfaceTokens.forStyle(style);
      for (final value in legacy) {
        expect(tokens.shapeFor(value), value,
            reason: '${style.name} must keep its literal $value');
      }
    }
    final stadium = SurfaceTokens.forStyle(SurfaceStyle.stadium);
    // Micro surfaces (category icons, picker chips, guides) take the look's
    // pill scale; none of them keep a square 2-6px corner.
    for (final value in <double>[2, 3, 4, 5, 6]) {
      expect(stadium.shapeFor(value), greaterThanOrEqualTo(8),
          reason: 'micro radius $value must round into the look');
    }
    expect(stadium.shapeFor(1), 2, reason: 'accent bars stay bars');
    expect(stadium.shapeFor(8), 16, reason: 'quality badge');
    expect(stadium.shapeFor(12), 22, reason: 'dialogs already converted');
  });

  testWidgets('a micro surface reads the look through lookTokens',
      (tester) async {
    for (final (style, expected) in [
      (SurfaceStyle.classic, 8.0),
      (SurfaceStyle.modern, 8.0),
      (SurfaceStyle.stadium, 16.0),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      await storage.setSurfaceStyleId(style.name);
      final prefs = AppPreferences(storage);
      await prefs.init();
      await tester.pumpWidget(MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider<AppPreferences>.value(value: prefs),
          ],
          child: MaterialApp(
              theme: buildAppTheme(prefs.palette, surfaceStyle: prefs.surfaceStyle),
              home: Builder(builder: (context) {
                final tokens = lookTokens(context);
                return Container(
                    key: const ValueKey('micro-surface'),
                    decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(tokens.shapeFor(8))));
              }))));
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(
          find.byKey(const ValueKey('micro-surface')));
      final radius = (box.decoration as BoxDecoration).borderRadius as BorderRadius;
      expect(radius.topLeft.x, expected,
          reason: '${style.name} micro surface radius');
      prefs.dispose();
    }
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
