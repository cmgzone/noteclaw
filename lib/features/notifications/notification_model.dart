class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime? readAt;
  final String? actionUrl;
  final String? senderId;
  final String? senderUsername;
  final String? senderAvatarUrl;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.isRead = false,
    this.readAt,
    this.actionUrl,
    this.senderId,
    this.senderUsername,
    this.senderAvatarUrl,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      userId: json['userId'],
      type: json['type'],
      title: json['title'],
      body: json['body'],
      data: json['data'],
      isRead: json['isRead'] ?? false,
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
      actionUrl: json['actionUrl'],
      senderId: json['senderId'],
      senderUsername: json['senderUsername'],
      senderAvatarUrl: json['senderAvatarUrl'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  AppNotification copyWith({bool? isRead, DateTime? readAt}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      actionUrl: actionUrl,
      senderId: senderId,
      senderUsername: senderUsername,
      senderAvatarUrl: senderAvatarUrl,
      createdAt: createdAt,
    );
  }

  // ==================== PROACTIVE NOTIFICATION HELPERS ====================

  /// Check if this is a proactive AI-generated notification
  bool get isProactive =>
      type == 'suggestion' || type == 'insight' || type == 'ai_reminder';

  /// Check if this is a suggestion notification
  bool get isSuggestion => type == 'suggestion';

  /// Check if this is an insight notification
  bool get isInsight => type == 'insight';

  /// Check if this is an AI reminder
  bool get isAIReminder => type == 'ai_reminder';

  /// Get the priority from notification data (high, medium, low)
  String get priority => data?['priority'] ?? 'medium';

  /// Check if this is a high-priority notification
  bool get isHighPriority => priority == 'high';

  /// Get the suggested action type from notification data
  String? get suggestedActionType => data?['actionType'];

  bool get isAdminNotification => data?['adminNotification'] == true;

  bool get shouldShowPopup => data?['showPopup'] == true;

  String get popupStyle => (data?['popupStyle'] as String?) ?? 'dialog';

  String? get popupActionLabel => data?['actionLabel'] as String?;

  /// Get notification category for grouping
  String get category {
    if (isProactive) return 'ai_assistant';
    if (type == 'friend_request' || type == 'friend_accepted') return 'social';
    if (type == 'achievement' || type == 'badge') return 'gamification';
    if (type == 'message' || type == 'group_message') return 'messages';
    if (type == 'study_reminder') return 'study';
    return 'system';
  }
}

class NotificationSettings {
  final bool messagesEnabled;
  final bool friendRequestsEnabled;
  final bool achievementsEnabled;
  final bool groupInvitesEnabled;
  final bool groupMessagesEnabled;
  final bool studyRemindersEnabled;
  final bool systemEnabled;
  final bool emailNotifications;
  final bool pushNotifications;
  final String? quietHoursStart;
  final String? quietHoursEnd;

  NotificationSettings({
    this.messagesEnabled = true,
    this.friendRequestsEnabled = true,
    this.achievementsEnabled = true,
    this.groupInvitesEnabled = true,
    this.groupMessagesEnabled = true,
    this.studyRemindersEnabled = true,
    this.systemEnabled = true,
    this.emailNotifications = false,
    this.pushNotifications = true,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      messagesEnabled: json['messagesEnabled'] ?? true,
      friendRequestsEnabled: json['friendRequestsEnabled'] ?? true,
      achievementsEnabled: json['achievementsEnabled'] ?? true,
      groupInvitesEnabled: json['groupInvitesEnabled'] ?? true,
      groupMessagesEnabled: json['groupMessagesEnabled'] ?? true,
      studyRemindersEnabled: json['studyRemindersEnabled'] ?? true,
      systemEnabled: json['systemEnabled'] ?? true,
      emailNotifications: json['emailNotifications'] ?? false,
      pushNotifications: json['pushNotifications'] ?? true,
      quietHoursStart: json['quietHoursStart'],
      quietHoursEnd: json['quietHoursEnd'],
    );
  }

  Map<String, dynamic> toJson() => {
        'messagesEnabled': messagesEnabled,
        'friendRequestsEnabled': friendRequestsEnabled,
        'achievementsEnabled': achievementsEnabled,
        'groupInvitesEnabled': groupInvitesEnabled,
        'groupMessagesEnabled': groupMessagesEnabled,
        'studyRemindersEnabled': studyRemindersEnabled,
        'systemEnabled': systemEnabled,
        'emailNotifications': emailNotifications,
        'pushNotifications': pushNotifications,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
      };
}
