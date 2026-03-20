import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_service.dart';
import 'notification_model.dart';

class NotificationState {
  final List<AppNotification> notifications;
  final List<AppNotification> popupQueue;
  final int unreadCount;
  final int total;
  final bool isLoading;
  final String? error;
  final NotificationSettings? settings;

  NotificationState({
    this.notifications = const [],
    this.popupQueue = const [],
    this.unreadCount = 0,
    this.total = 0,
    this.isLoading = false,
    this.error,
    this.settings,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    List<AppNotification>? popupQueue,
    int? unreadCount,
    int? total,
    bool? isLoading,
    String? error,
    NotificationSettings? settings,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      popupQueue: popupQueue ?? this.popupQueue,
      unreadCount: unreadCount ?? this.unreadCount,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      settings: settings ?? this.settings,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final ApiService _api;
  Timer? _pollTimer;
  final Set<String> _knownNotificationIds = <String>{};
  final Set<String> _queuedPopupIds = <String>{};
  bool _hasSeededNotifications = false;

  NotificationNotifier(this._api) : super(NotificationState()) {
    _startPolling();
    Future.microtask(bootstrap);
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollForUpdates();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> bootstrap() async {
    await _pollForUpdates();
  }

  List<AppNotification> _parseNotifications(dynamic rawNotifications) {
    final items = rawNotifications as List? ?? const [];
    return items
        .map((item) =>
            AppNotification.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  List<AppNotification> _mergeLatestNotifications(
    List<AppNotification> incoming,
  ) {
    if (state.notifications.isEmpty) return incoming;

    final incomingIds = incoming.map((notification) => notification.id).toSet();
    return [
      ...incoming,
      ...state.notifications
          .where((notification) => !incomingIds.contains(notification.id)),
    ];
  }

  void _syncSnapshot({
    required List<AppNotification> incoming,
    required int unreadCount,
    required int total,
    bool replaceExisting = false,
    bool isLoading = false,
  }) {
    final mergedNotifications =
        replaceExisting ? incoming : _mergeLatestNotifications(incoming);
    final shouldSeed = !_hasSeededNotifications;

    final newNotifications = shouldSeed
        ? const <AppNotification>[]
        : incoming
            .where((notification) =>
                !_knownNotificationIds.contains(notification.id))
            .toList();

    if (shouldSeed) {
      _hasSeededNotifications = true;
    }

    _knownNotificationIds.addAll(
      incoming.map((notification) => notification.id),
    );

    final newPopupNotifications = newNotifications
        .where(
          (notification) =>
              notification.shouldShowPopup &&
              !_queuedPopupIds.contains(notification.id),
        )
        .toList();

    if (newPopupNotifications.isNotEmpty) {
      _queuedPopupIds.addAll(
        newPopupNotifications.map((notification) => notification.id),
      );
    }

    state = state.copyWith(
      notifications: mergedNotifications,
      popupQueue: newPopupNotifications.isEmpty
          ? state.popupQueue
          : [...state.popupQueue, ...newPopupNotifications],
      unreadCount: unreadCount,
      total: total,
      isLoading: isLoading,
      error: null,
    );
  }

  void _resetStateForSignedOutUser() {
    _knownNotificationIds.clear();
    _queuedPopupIds.clear();
    _hasSeededNotifications = false;
    state = NotificationState();
  }

  Future<void> _pollForUpdates() async {
    try {
      final token = await _api.getToken();
      if (token == null) {
        _resetStateForSignedOutUser();
        return;
      }

      final response = await _api.get<Map<String, dynamic>>(
        '/notifications',
        queryParameters: {'limit': 10},
      );

      _syncSnapshot(
        incoming: _parseNotifications(response['notifications']),
        unreadCount: response['unreadCount'] ?? state.unreadCount,
        total: response['total'] ?? state.total,
      );
    } catch (_) {
      // Polling is best-effort. Leave current state as-is.
    }
  }

  Future<void> fetchNotifications({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(isLoading: true, error: null);
    final token = await _api.getToken();
    if (token == null) {
      _resetStateForSignedOutUser();
      return;
    }
    try {
      final response = await _api.get('/notifications');
      _syncSnapshot(
        incoming: _parseNotifications(response['notifications']),
        unreadCount: response['unreadCount'] ?? 0,
        total: response['total'] ?? 0,
        replaceExisting: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> fetchUnreadCount() async {
    try {
      final token = await _api.getToken();
      if (token == null) {
        if (state.unreadCount != 0) {
          state = state.copyWith(unreadCount: 0);
        }
        return;
      }
      final response = await _api.get('/notifications/unread-count');
      state = state.copyWith(unreadCount: response['unreadCount'] ?? 0);
    } catch (e) {
      // Silently fail for polling
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _api.patch('/notifications/$notificationId/read', {});

      final updated = state.notifications.map((n) {
        if (n.id == notificationId) {
          return n.copyWith(isRead: true, readAt: DateTime.now());
        }
        return n;
      }).toList();

      state = state.copyWith(
        notifications: updated,
        popupQueue: state.popupQueue
            .where((notification) => notification.id != notificationId)
            .toList(),
        unreadCount: (state.unreadCount - 1).clamp(0, state.total),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _api.post('/notifications/mark-all-read', {});

      final updated = state.notifications.map((n) {
        return n.copyWith(isRead: true, readAt: DateTime.now());
      }).toList();

      state = state.copyWith(
        notifications: updated,
        popupQueue: const [],
        unreadCount: 0,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _api.delete('/notifications/$notificationId');

      final notificationIndex = state.notifications.indexWhere(
        (notification) => notification.id == notificationId,
      );
      final wasUnread = notificationIndex >= 0
          ? !state.notifications[notificationIndex].isRead
          : false;

      final updated =
          state.notifications.where((n) => n.id != notificationId).toList();

      state = state.copyWith(
        notifications: updated,
        popupQueue: state.popupQueue
            .where((notification) => notification.id != notificationId)
            .toList(),
        total: state.total - 1,
        unreadCount: wasUnread ? state.unreadCount - 1 : state.unreadCount,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> fetchSettings() async {
    try {
      final response = await _api.get('/notifications/settings');
      final settings = NotificationSettings.fromJson(response['settings']);
      state = state.copyWith(settings: settings);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateSettings(Map<String, dynamic> updates) async {
    try {
      final response = await _api.patch('/notifications/settings', updates);
      final settings = NotificationSettings.fromJson(response['settings']);
      state = state.copyWith(settings: settings);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  void consumePopup(String notificationId) {
    state = state.copyWith(
      popupQueue: state.popupQueue
          .where((notification) => notification.id != notificationId)
          .toList(),
    );
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(ref.watch(apiServiceProvider));
});

// Simple unread count provider for badge display
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationProvider).unreadCount;
});
