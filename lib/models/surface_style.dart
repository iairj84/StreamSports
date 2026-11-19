import 'package:flutter/painting.dart';

/// Geometry dimension of the visual theme — corner roundness, focus
/// treatment, type treatment and card anatomy — independent of the colour
/// palette, which stays on [CyberpunkPalette].
///
/// Classic preserves the existing look so stored layouts and geometry tests
/// keep passing; Modern rounds surfaces up and replaces the thick focus
/// outline with a thinner border plus a glow. Stadium Night is a whole
/// visual language rather than a tweak: pill surfaces, ring-only focus with
/// a stronger halo, uppercase letterspaced labels, heavier titles and a
/// dedicated score size, so choosing it reads as a different app without
/// changing a single row, card or navigation path.
enum SurfaceStyle {
  classic,
  modern,
  stadium,
}

/// Per-style tokens read by widgets instead of hardcoded radii, focus
/// widths and type sizes.
class SurfaceTokens {
  const SurfaceTokens({
    required this.rowRadius,
    required this.blockRadius,
    required this.settingsRowRadius,
    required this.focusBorderWidth,
    required this.focusGlowBlur,
    required this.focusGlowAlpha,
    required this.focusRingOnly,
    required this.uppercaseLabels,
    required this.labelLetterSpacing,
    required this.titleWeight,
    required this.scoreSize,
    required this.uppercasesStatus,
    required this.cardRadius,
    required this.dialogRadius,
    required this.menuRadius,
    required this.inputRadius,
    required this.buttonRadius,
    required this.sheetRadius,
  });

  /// Corner radius of a player sheet or compact dialog.
  final double sheetRadius;

  /// Corner radius for cards and panels.
  final double cardRadius;

  /// Corner radius for dialogs and player sheets.
  final double dialogRadius;

  /// Corner radius for popup menus, tooltips, snackbars and chips.
  final double menuRadius;

  /// Corner radius for text fields.
  final double inputRadius;

  /// Corner radius for buttons.
  final double buttonRadius;

  /// Outer corner radius for list rows and small cards.
  final double rowRadius;

  /// Corner radius for small packed elements — guide blocks, chips,
  /// logo tiles — where the full row radius would turn them into pills.
  final double blockRadius;

  /// Radius of a settings tile inside its section card. Classic keeps its
  /// own 4px so the legacy look is byte-identical.
  final double settingsRowRadius;

  /// Focused-state border width.
  final double focusBorderWidth;

  /// Focused-state glow spread; zero means no glow on Classic.
  final double focusGlowBlur;

  /// Focused-state glow strength as a fraction.
  final double focusGlowAlpha;

  /// When true, focus is shown by border and halo only — the surface keeps
  /// its resting colour instead of flipping to an accent fill. This is what
  /// makes Stadium Night read as a modern streaming UI rather than a
  /// highlighted list.
  final bool focusRingOnly;

  /// Draw section headings in uppercase with extra tracking.
  final bool uppercaseLabels;

  /// Tracking for those headings, in logical pixels.
  final double labelLetterSpacing;

  /// Weight for primary card text (team names, fixture titles).
  final FontWeight titleWeight;

  /// Size of a live/final score on a card.
  final double scoreSize;

  /// Draw card status words (LIVE, FINAL, Q3) as small letterspaced caps.
  final bool uppercasesStatus;

  /// True for the styles that round surfaces as a deliberate shape rather
  /// than the legacy square corners.
  bool get rounded => this != classic;

  /// Retained for call sites that predate [rounded].
  bool get isModern => this == modern;

  static const classic = SurfaceTokens(
      rowRadius: 3,
      blockRadius: 2,
      settingsRowRadius: 4,
      focusBorderWidth: 2.5,
      focusGlowBlur: 0,
      focusGlowAlpha: 0,
      focusRingOnly: false,
      uppercaseLabels: false,
      labelLetterSpacing: 0,
      titleWeight: FontWeight.w600,
      scoreSize: 13,
      uppercasesStatus: false,
      cardRadius: 10,
      dialogRadius: 12,
      menuRadius: 10,
      inputRadius: 8,
      buttonRadius: 8,
      sheetRadius: 8);

  static const modern = SurfaceTokens(
      rowRadius: 10,
      blockRadius: 6,
      settingsRowRadius: 10,
      focusBorderWidth: 1,
      focusGlowBlur: 14,
      focusGlowAlpha: 0.32,
      focusRingOnly: false,
      uppercaseLabels: false,
      labelLetterSpacing: 0,
      titleWeight: FontWeight.w600,
      scoreSize: 13,
      uppercasesStatus: false,
      cardRadius: 10,
      dialogRadius: 12,
      menuRadius: 10,
      inputRadius: 8,
      buttonRadius: 8,
      sheetRadius: 12);

  /// Direction B: pill shapes, ring-only focus, heavy titles and small
  /// tracked caps for every label that used to be a sentence-case whisper.
  static const stadium = SurfaceTokens(
      rowRadius: 18,
      blockRadius: 12,
      settingsRowRadius: 14,
      focusBorderWidth: 2,
      focusGlowBlur: 22,
      focusGlowAlpha: 0.42,
      focusRingOnly: true,
      uppercaseLabels: true,
      labelLetterSpacing: 1.1,
      titleWeight: FontWeight.w800,
      scoreSize: 19,
      uppercasesStatus: true,
      cardRadius: 16,
      dialogRadius: 22,
      menuRadius: 18,
      inputRadius: 14,
      buttonRadius: 12,
      sheetRadius: 22);

  static SurfaceTokens forStyle(SurfaceStyle style) => switch (style) {
        SurfaceStyle.classic => classic,
        SurfaceStyle.modern => modern,
        SurfaceStyle.stadium => stadium,
      };

  /// Stored ids are the enum names; anything unknown reads as Classic so an
  /// old or mistyped value can never strand the UI on an unknown look.
  static SurfaceStyle fromId(String? id) {
    for (final style in SurfaceStyle.values) {
      if (style.name == id) return style;
    }
    return SurfaceStyle.classic;
  }
}
