/// Geometry dimension of the visual theme — corner roundness, focus
/// treatment — independent of the colour palette, which stays on
/// [CyberpunkPalette]. Classic preserves the existing look so stored
/// layouts and geometry tests keep passing; Modern rounds surfaces up and
/// replaces the thick focus outline with a thinner border plus a glow.
enum SurfaceStyle {
  classic,
  modern,
}

/// Per-style geometry tokens read by widgets instead of hardcoded radii
/// and focus widths.
class SurfaceTokens {
  const SurfaceTokens({
    required this.rowRadius,
    required this.blockRadius,
    required this.focusBorderWidth,
    required this.focusGlowBlur,
    required this.focusGlowAlpha,
  });

  /// Outer corner radius for list rows and small cards.
  final double rowRadius;

  /// Corner radius for small packed elements — guide blocks, chips,
  /// logo tiles — where the full row radius would turn them into pills.
  final double blockRadius;

  /// True only for the modern style, for call sites whose classic radius
  /// differs from the matching token and must keep the old value there.
  bool get isModern => this == modern;

  /// Focused-state border width.
  final double focusBorderWidth;

  /// Focused-state glow spread; zero means no glow on Classic.
  final double focusGlowBlur;

  /// Focused-state glow strength as a fraction.
  final double focusGlowAlpha;

  static const classic = SurfaceTokens(
      rowRadius: 3,
      blockRadius: 2,
      focusBorderWidth: 2.5,
      focusGlowBlur: 0,
      focusGlowAlpha: 0);

  static const modern = SurfaceTokens(
      rowRadius: 10,
      blockRadius: 6,
      focusBorderWidth: 1,
      focusGlowBlur: 14,
      focusGlowAlpha: 0.32);

  static SurfaceTokens forStyle(SurfaceStyle style) => switch (style) {
        SurfaceStyle.classic => classic,
        SurfaceStyle.modern => modern,
      };

  /// Stored ids are the enum names; anything unknown reads as Classic so an
  /// old or mistyped value can never strand the UI on an unknown look.
  static SurfaceStyle fromId(String? id) =>
      id == SurfaceStyle.modern.name ? SurfaceStyle.modern : SurfaceStyle.classic;
}
