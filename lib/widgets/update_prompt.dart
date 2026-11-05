import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/app_update_service.dart';

/// What the viewer chose in the startup update prompt.
enum UpdatePromptChoice { update, later, skip }

/// Offers a newer release at launch. Shown from the Navigator rather than a
/// screen because the check runs outside any route.
Future<UpdatePromptChoice?> showUpdatePrompt(
  BuildContext context,
  AppRelease release,
  String currentLabel,
) =>
    showDialog<UpdatePromptChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Update available')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
                '{new} is ready. This device is running {current}.',
                {'new': release.label, 'current': currentLabel})),
            const SizedBox(height: 12),
            Text(
                tr('The update downloads inside the app and installs over this one. Playlists, favourites and guide data stay as they are.'),
                style: Theme.of(dialogContext).textTheme.bodySmall),
            if (release.sizeLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tr('Download size: {size}', {'size': release.sizeLabel}),
                  style: Theme.of(dialogContext).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, UpdatePromptChoice.skip),
            child: Text(tr('Skip this build')),
          ),
          TextButton(
            autofocus: true,
            onPressed: () =>
                Navigator.pop(dialogContext, UpdatePromptChoice.later),
            child: Text(tr('Later')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, UpdatePromptChoice.update),
            child: Text(tr('Update now')),
          ),
        ],
      ),
    );
