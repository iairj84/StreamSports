import 'settings_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/surface_style.dart';
import '../services/app_preferences.dart';

/// A small colored accent bar + text — the same "this section belongs to
/// the palette" treatment used on TV browse category headers and season
/// headers, reused here so Settings doesn't look like a different, older
/// app bolted onto the redesigned browse screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (SettingsScope.contains(context)) {
      return Text(text,
          style: style ??
              TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    final tokens = SurfaceTokens.forStyle(
        context.watch<AppPreferences?>()?.surfaceStyle ??
            SurfaceStyle.classic);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: tokens.uppercaseLabels ? 4 : 3,
            height: 16,
            color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            tokens.uppercaseLabels ? text.toUpperCase() : text,
            style: style ??
                Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: tokens.uppercaseLabels ? 12 : null,
                    letterSpacing: tokens.labelLetterSpacing),
          ),
        ),
      ],
    );
  }
}
