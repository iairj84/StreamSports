import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/surface_style.dart';
import '../services/app_preferences.dart';
import '../utils/interface_colors.dart';

/// Translucent grouping panel for related settings rows, retaining contrast over the shared
/// background.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel(
      {super.key,
      required this.children,
      this.padding = const EdgeInsets.all(16)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SurfaceTokens.forStyle(
        context.watch<AppPreferences?>()?.surfaceStyle ??
            SurfaceStyle.classic);
    return Container(
      width: double.infinity,
      // A row with its own solid focus fill (TvSwitchListTile, used with
      // zero padding here so it can sit flush against the panel edges)
      // would otherwise square off past these rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: interfaceColor(context, Colors.white).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(tokens.rowRadius),
        border: Border.all(color: interfaceColor(context, Colors.white).withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}
