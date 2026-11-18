import 'package:flutter/material.dart';

/// Touch-free state marker: included is checked, excluded is empty.
class ShownMark extends StatelessWidget {
  const ShownMark({
    super.key,
    required this.shown,
    this.shownLabel = 'Shown in Sports',
    this.hiddenLabel = 'Hidden from Sports',
  });
  final bool shown;
  final String shownLabel, hiddenLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: shown ? shownLabel : hiddenLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
            shown ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: shown ? colors.primary : colors.onSurfaceVariant),
      ),
    );
  }
}
