import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'notification_model.dart';
import 'notification_provider.dart';

class AppNotificationOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const AppNotificationOverlay({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AppNotificationOverlay> createState() =>
      _AppNotificationOverlayState();
}

class _AppNotificationOverlayState
    extends ConsumerState<AppNotificationOverlay> {
  bool _isShowingPopup = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(notificationProvider.notifier).bootstrap();
    });
  }

  Future<void> _maybeShowNextPopup(NotificationState state) async {
    if (!mounted || _isShowingPopup || state.popupQueue.isEmpty) return;
    await _showPopup(state.popupQueue.first);
  }

  Future<void> _showPopup(AppNotification notification) async {
    if (!mounted || _isShowingPopup) return;

    setState(() => _isShowingPopup = true);
    final theme = Theme.of(context);
    final hasAction =
        notification.actionUrl != null && notification.actionUrl!.isNotEmpty;
    final popupActionLabel = notification.popupActionLabel?.trim();
    final actionLabel =
        popupActionLabel != null && popupActionLabel.isNotEmpty
            ? popupActionLabel
            : 'Open';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.campaign_rounded,
          color: theme.colorScheme.primary,
          size: 32,
        ),
        title: Text(notification.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body != null && notification.body!.trim().isNotEmpty)
              Text(notification.body!),
            if (hasAction) ...[
              const SizedBox(height: 12),
              Text(
                'Tap $actionLabel to open the linked page in the app.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
            child: const Text('Dismiss'),
          ),
          if (hasAction)
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop('open'),
              icon: const Icon(Icons.open_in_new),
              label: Text(actionLabel),
            ),
        ],
      ),
    );

    if (!mounted) return;

    ref.read(notificationProvider.notifier).consumePopup(notification.id);

    if (result == 'open' && hasAction) {
      if (!notification.isRead) {
        unawaited(
          ref.read(notificationProvider.notifier).markAsRead(notification.id),
        );
      }
      context.push(notification.actionUrl!);
    }

    if (mounted) {
      setState(() => _isShowingPopup = false);
      Future.microtask(
        () => _maybeShowNextPopup(ref.read(notificationProvider)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationState = ref.watch(notificationProvider);

    ref.listen<NotificationState>(notificationProvider, (_, next) {
      _maybeShowNextPopup(next);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowNextPopup(notificationState);
    });

    return widget.child;
  }
}
