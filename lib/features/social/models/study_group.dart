import 'package:noteclaw/core/utils/app_logger.dart';
import 'package:noteclaw/core/utils/json_parsing.dart';

const _logger = AppLogger('StudyGroup');

// ============================================================================
// ENUMS
// ============================================================================

/// Role types for group members with type safety
enum GroupRole {
  owner,
  admin,
  moderator,
  member;

  /// Parse role from string, defaults to member if invalid
  static GroupRole fromString(String? role) {
    if (role == null) return GroupRole.member;
    return GroupRole.values.firstWhere(
      (r) => r.name == role,
      orElse: () => GroupRole.member,
    );
  }

  /// Check if this role has admin privileges
  bool get hasAdminPrivileges =>
      this == GroupRole.owner || this == GroupRole.admin;

  /// Check if this role has moderation privileges
  bool get hasModerationPrivileges =>
      this == GroupRole.owner ||
      this == GroupRole.admin ||
      this == GroupRole.moderator;
}

// ============================================================================
// CONSTANTS & LIMITS
// ============================================================================

/// Validation limits for study groups
class GroupLimits {
  GroupLimits._();

  static const int minMembers = 1;
  static const int maxMembers = 500;
  static const int minDuration = 1;
  static const int maxDuration = 1440; // 24 hours in minutes
  static const int maxNameLength = 100;
  static const int maxDescriptionLength = 1000;
}

/// Default values for study groups
class GroupDefaults {
  GroupDefaults._();

  static const String icon = '📚';
  static const int maxMembers = 50;
  static const int memberCount = 1;
  static const int durationMinutes = 60;
}

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/// Validates and clamps a count value within bounds
int _validateCount(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Validates URL format, returns null if invalid or unsafe scheme
/// Only allows http/https schemes and validates host presence
String? _validateUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  try {
    final uri = Uri.parse(url);
    if (!uri.hasScheme) return null;

    final scheme = uri.scheme.toLowerCase();
    // Only allow safe schemes
    if (!const {'http', 'https'}.contains(scheme)) return null;

    // Validate host exists
    if (uri.host.isEmpty) return null;

    // Check for path traversal attempts
    if (uri.path.contains('..') || uri.path.contains('//')) return null;

    return uri.toString(); // Return normalized URL
  } catch (_) {
    return null;
  }
}

/// Pre-compiled email regex for performance
final _emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');

/// Basic email validation with length check
bool _isValidEmail(String email) {
  if (email.isEmpty || email.length > 254) return false;
  return _emailRegex.hasMatch(email);
}

// ============================================================================
// STUDY GROUP MODEL
// ============================================================================

/// Represents a study group entity.
///
/// ## JSON Structure
/// ```json
/// {
///   "id": "uuid",
///   "name": "Study Group Name",
///   "description": "Optional description",
///   "owner_id": "user-uuid",
///   "owner_username": "username",
///   "icon": "📚",
///   "cover_image_url": "https://example.com/image.jpg",
///   "is_public": false,
///   "max_members": 50,
///   "member_count": 1,
///   "user_role": "owner|admin|member",
///   "created_at": "2024-01-01T00:00:00Z"
/// }
/// ```
class StudyGroup {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String? ownerUsername;
  final String icon;
  final String? coverImageUrl;
  final bool isPublic;
  final int maxMembers;
  final int memberCount;
  final GroupRole role;
  final DateTime createdAt;

  const StudyGroup._({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.ownerUsername,
    required this.icon,
    this.coverImageUrl,
    required this.isPublic,
    required this.maxMembers,
    required this.memberCount,
    required this.role,
    required this.createdAt,
  });

  /// Creates a StudyGroup with validation
  factory StudyGroup({
    required String id,
    required String name,
    String? description,
    required String ownerId,
    String? ownerUsername,
    String icon = GroupDefaults.icon,
    String? coverImageUrl,
    bool isPublic = false,
    int maxMembers = GroupDefaults.maxMembers,
    int memberCount = GroupDefaults.memberCount,
    GroupRole role = GroupRole.member,
    required DateTime createdAt,
  }) {
    final validatedMaxMembers = _validateCount(
        maxMembers, GroupLimits.minMembers, GroupLimits.maxMembers);
    final validatedMemberCount =
        _validateCount(memberCount, 0, validatedMaxMembers);

    return StudyGroup._(
      id: id,
      name: name.length > GroupLimits.maxNameLength
          ? name.substring(0, GroupLimits.maxNameLength)
          : name,
      description: description != null &&
              description.length > GroupLimits.maxDescriptionLength
          ? description.substring(0, GroupLimits.maxDescriptionLength)
          : description,
      ownerId: ownerId,
      ownerUsername: ownerUsername,
      icon: icon.isEmpty ? GroupDefaults.icon : icon,
      coverImageUrl: _validateUrl(coverImageUrl),
      isPublic: isPublic,
      maxMembers: validatedMaxMembers,
      memberCount: validatedMemberCount,
      role: role,
      createdAt: createdAt,
    );
  }

  factory StudyGroup.fromJson(Map<String, dynamic> json) {
    final id = json.getString('id');
    final name = json.getString('name');
    final ownerId = json.getString('owner_id', 'ownerId');

    if (id == null || id.isEmpty) {
      throw const FormatException('StudyGroup: Missing required field "id"');
    }
    if (name == null || name.isEmpty) {
      throw const FormatException('StudyGroup: Missing required field "name"');
    }
    if (ownerId == null || ownerId.isEmpty) {
      throw const FormatException(
          'StudyGroup: Missing required field "ownerId"');
    }

    try {
      return StudyGroup(
        id: id,
        name: name,
        description: json.getString('description'),
        ownerId: ownerId,
        ownerUsername: json.getString('owner_username', 'ownerUsername'),
        icon: json.getString('icon') ?? GroupDefaults.icon,
        coverImageUrl: json.getString('cover_image_url', 'coverImageUrl'),
        isPublic: json.getBool('is_public', 'isPublic'),
        maxMembers:
            json.getInt('max_members', 'maxMembers', GroupDefaults.maxMembers),
        memberCount: json.getInt(
            'member_count', 'memberCount', GroupDefaults.memberCount),
        role: GroupRole.fromString(json.getString('user_role', 'userRole')),
        createdAt: json.getDateTimeOrNow('created_at', 'createdAt'),
      );
    } catch (e, stack) {
      _logger.error('Error parsing StudyGroup from JSON', e, stack);
      rethrow;
    }
  }

  /// Safe factory that returns null on parse failure with logging
  static StudyGroup? tryFromJson(Map<String, dynamic> json) {
    try {
      return StudyGroup.fromJson(json);
    } catch (e) {
      _logger.warning('StudyGroup.tryFromJson failed: $e');
      return null;
    }
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'owner_id': ownerId,
        'owner_username': ownerUsername,
        'icon': icon,
        'cover_image_url': coverImageUrl,
        'is_public': isPublic,
        'max_members': maxMembers,
        'member_count': memberCount,
        'user_role': role.name,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isOwner => role == GroupRole.owner;
  bool get isAdmin => role.hasAdminPrivileges;
  bool get isModerator => role == GroupRole.moderator;

  /// Filter upcoming sessions from a list using shared DateTime reference
  static List<StudySession> filterUpcomingSessions(
    List<StudySession> sessions, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    return sessions.where((s) => s.isUpcomingFrom(ref)).toList();
  }
}

// ============================================================================
// GROUP MEMBER MODEL
// ============================================================================

/// Represents a member of a study group.
///
/// ## JSON Structure
/// ```json
/// {
///   "id": "uuid",
///   "group_id": "group-uuid",
///   "user_id": "user-uuid",
///   "username": "johndoe",
///   "email": "john@example.com",
///   "avatar_url": "https://example.com/avatar.jpg",
///   "role": "owner|admin|member",
///   "joined_at": "2024-01-01T00:00:00Z"
/// }
/// ```
class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String username;
  final String? email;
  final String? avatarUrl;
  final GroupRole role;
  final DateTime joinedAt;

  const GroupMember._({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.username,
    this.email,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  /// Creates a GroupMember with validation
  factory GroupMember({
    required String id,
    required String groupId,
    required String userId,
    required String username,
    String? email,
    String? avatarUrl,
    GroupRole role = GroupRole.member,
    required DateTime joinedAt,
  }) {
    // Validate email if provided
    String? validatedEmail;
    if (email != null && email.isNotEmpty) {
      if (_isValidEmail(email)) {
        validatedEmail = email;
      } else {
        _logger.warning('Invalid email format for user $username');
      }
    }

    return GroupMember._(
      id: id,
      groupId: groupId,
      userId: userId,
      username: username,
      email: validatedEmail,
      avatarUrl: _validateUrl(avatarUrl),
      role: role,
      joinedAt: joinedAt,
    );
  }

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final id = json.getString('id');
    final username = json.getString('username');

    if (id == null || id.isEmpty) {
      throw const FormatException('GroupMember: Missing required field "id"');
    }
    if (username == null || username.isEmpty) {
      throw const FormatException(
          'GroupMember: Missing required field "username"');
    }

    try {
      return GroupMember(
        id: id,
        groupId: json.getStringOrDefault('group_id', 'groupId'),
        userId: json.getStringOrDefault('user_id', 'userId'),
        username: username,
        email: json.getString('email'),
        avatarUrl: json.getString('avatar_url', 'avatarUrl'),
        role: GroupRole.fromString(json.getString('role')),
        joinedAt: json.getDateTimeOrNow('joined_at', 'joinedAt'),
      );
    } catch (e, stack) {
      _logger.error('Error parsing GroupMember from JSON', e, stack);
      rethrow;
    }
  }

  /// Safe factory that returns null on parse failure with logging
  static GroupMember? tryFromJson(Map<String, dynamic> json) {
    try {
      return GroupMember.fromJson(json);
    } catch (e) {
      _logger.warning('GroupMember.tryFromJson failed: $e');
      return null;
    }
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'user_id': userId,
        'username': username,
        'email': email,
        'avatar_url': avatarUrl,
        'role': role.name,
        'joined_at': joinedAt.toIso8601String(),
      };

  bool get isOwner => role == GroupRole.owner;
  bool get isAdmin => role.hasAdminPrivileges;
  bool get isModerator => role == GroupRole.moderator;
}

// ============================================================================
// STUDY SESSION MODEL
// ============================================================================

/// Represents a scheduled study session.
///
/// ## JSON Structure
/// ```json
/// {
///   "id": "uuid",
///   "group_id": "group-uuid",
///   "title": "Session Title",
///   "description": "Optional description",
///   "scheduled_at": "2024-01-01T10:00:00Z",
///   "duration_minutes": 60,
///   "meeting_url": "https://meet.example.com/abc",
///   "created_by": "user-uuid",
///   "created_by_username": "johndoe",
///   "created_at": "2024-01-01T00:00:00Z"
/// }
/// ```
class StudySession {
  final String id;
  final String groupId;
  final String title;
  final String? description;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String? meetingUrl;
  final String createdBy;
  final String? createdByUsername;
  final DateTime createdAt;

  const StudySession._({
    required this.id,
    required this.groupId,
    required this.title,
    this.description,
    required this.scheduledAt,
    required this.durationMinutes,
    this.meetingUrl,
    required this.createdBy,
    this.createdByUsername,
    required this.createdAt,
  });

  /// Creates a StudySession with validation
  factory StudySession({
    required String id,
    required String groupId,
    required String title,
    String? description,
    required DateTime scheduledAt,
    int durationMinutes = GroupDefaults.durationMinutes,
    String? meetingUrl,
    required String createdBy,
    String? createdByUsername,
    required DateTime createdAt,
  }) {
    return StudySession._(
      id: id,
      groupId: groupId,
      title: title.length > GroupLimits.maxNameLength
          ? title.substring(0, GroupLimits.maxNameLength)
          : title,
      description: description != null &&
              description.length > GroupLimits.maxDescriptionLength
          ? description.substring(0, GroupLimits.maxDescriptionLength)
          : description,
      scheduledAt: scheduledAt,
      durationMinutes: _validateCount(
          durationMinutes, GroupLimits.minDuration, GroupLimits.maxDuration),
      meetingUrl: _validateUrl(meetingUrl),
      createdBy: createdBy,
      createdByUsername: createdByUsername,
      createdAt: createdAt,
    );
  }

  factory StudySession.fromJson(Map<String, dynamic> json) {
    final id = json.getString('id');
    final title = json.getString('title');

    if (id == null || id.isEmpty) {
      throw const FormatException('StudySession: Missing required field "id"');
    }
    if (title == null || title.isEmpty) {
      throw const FormatException(
          'StudySession: Missing required field "title"');
    }

    try {
      return StudySession(
        id: id,
        groupId: json.getStringOrDefault('group_id', 'groupId'),
        title: title,
        description: json.getString('description'),
        scheduledAt: json.getDateTimeOrNow('scheduled_at', 'scheduledAt'),
        durationMinutes: json.getInt('duration_minutes', 'durationMinutes',
            GroupDefaults.durationMinutes),
        meetingUrl: json.getString('meeting_url', 'meetingUrl'),
        createdBy: json.getStringOrDefault('created_by', 'createdBy'),
        createdByUsername:
            json.getString('created_by_username', 'createdByUsername'),
        createdAt: json.getDateTimeOrNow('created_at', 'createdAt'),
      );
    } catch (e, stack) {
      _logger.error('Error parsing StudySession from JSON', e, stack);
      rethrow;
    }
  }

  /// Safe factory that returns null on parse failure with logging
  static StudySession? tryFromJson(Map<String, dynamic> json) {
    try {
      return StudySession.fromJson(json);
    } catch (e) {
      _logger.warning('StudySession.tryFromJson failed: $e');
      return null;
    }
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'title': title,
        'description': description,
        'scheduled_at': scheduledAt.toIso8601String(),
        'duration_minutes': durationMinutes,
        'meeting_url': meetingUrl,
        'created_by': createdBy,
        'created_by_username': createdByUsername,
        'created_at': createdAt.toIso8601String(),
      };

  /// Check if session is upcoming relative to [now].
  /// Pass a cached DateTime for better performance in list operations.
  bool isUpcomingFrom(DateTime now) => scheduledAt.isAfter(now);

  /// Check if session is upcoming (uses DateTime.now()).
  /// For batch operations, prefer [isUpcomingFrom] with a cached DateTime.
  bool get isUpcoming => isUpcomingFrom(DateTime.now());

  /// Get the end time of this session
  DateTime get endTime => scheduledAt.add(Duration(minutes: durationMinutes));

  /// Check if session is currently in progress
  bool isInProgressAt(DateTime now) =>
      now.isAfter(scheduledAt) && now.isBefore(endTime);
}

// ============================================================================
// GROUP INVITATION MODEL
// ============================================================================

/// Represents an invitation to join a study group.
///
/// ## JSON Structure
/// ```json
/// {
///   "id": "uuid",
///   "group_id": "group-uuid",
///   "group_name": "Study Group Name",
///   "group_icon": "📚",
///   "invited_by_username": "johndoe",
///   "created_at": "2024-01-01T00:00:00Z"
/// }
/// ```
class GroupInvitation {
  final String id;
  final String groupId;
  final String groupName;
  final String groupIcon;
  final String invitedByUsername;
  final DateTime createdAt;

  const GroupInvitation._({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.groupIcon,
    required this.invitedByUsername,
    required this.createdAt,
  });

  /// Creates a GroupInvitation with validation
  factory GroupInvitation({
    required String id,
    required String groupId,
    required String groupName,
    String groupIcon = GroupDefaults.icon,
    required String invitedByUsername,
    required DateTime createdAt,
  }) {
    return GroupInvitation._(
      id: id,
      groupId: groupId,
      groupName: groupName.length > GroupLimits.maxNameLength
          ? groupName.substring(0, GroupLimits.maxNameLength)
          : groupName,
      groupIcon: groupIcon.isEmpty ? GroupDefaults.icon : groupIcon,
      invitedByUsername: invitedByUsername,
      createdAt: createdAt,
    );
  }

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    final id = json.getString('id');
    final groupName = json.getString('group_name', 'groupName');
    final invitedByUsername =
        json.getString('invited_by_username', 'invitedByUsername');

    if (id == null || id.isEmpty) {
      throw const FormatException(
          'GroupInvitation: Missing required field "id"');
    }
    if (groupName == null || groupName.isEmpty) {
      throw const FormatException(
          'GroupInvitation: Missing required field "groupName"');
    }
    if (invitedByUsername == null || invitedByUsername.isEmpty) {
      throw const FormatException(
          'GroupInvitation: Missing required field "invitedByUsername"');
    }

    try {
      return GroupInvitation(
        id: id,
        groupId: json.getStringOrDefault('group_id', 'groupId'),
        groupName: groupName,
        groupIcon:
            json.getString('group_icon', 'groupIcon') ?? GroupDefaults.icon,
        invitedByUsername: invitedByUsername,
        createdAt: json.getDateTimeOrNow('created_at', 'createdAt'),
      );
    } catch (e, stack) {
      _logger.error('Error parsing GroupInvitation from JSON', e, stack);
      rethrow;
    }
  }

  /// Safe factory that returns null on parse failure with logging
  static GroupInvitation? tryFromJson(Map<String, dynamic> json) {
    try {
      return GroupInvitation.fromJson(json);
    } catch (e) {
      _logger.warning('GroupInvitation.tryFromJson failed: $e');
      return null;
    }
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'group_name': groupName,
        'group_icon': groupIcon,
        'invited_by_username': invitedByUsername,
        'created_at': createdAt.toIso8601String(),
      };
}

// ============================================================================
// GROUP BAN MODEL
// ============================================================================

/// Represents a banned user in a study group.
class GroupBan {
  final String id;
  final String groupId;
  final String userId;
  final String? username;
  final String? email;
  final String? avatarUrl;
  final String? reason;
  final String? bannedBy;
  final DateTime createdAt;

  const GroupBan({
    required this.id,
    required this.groupId,
    required this.userId,
    this.username,
    this.email,
    this.avatarUrl,
    this.reason,
    this.bannedBy,
    required this.createdAt,
  });

  factory GroupBan.fromJson(Map<String, dynamic> json) {
    final id = json.getString('id');
    final groupId = json.getStringOrDefault('group_id', 'groupId');
    final userId = json.getStringOrDefault('user_id', 'userId');

    if (id == null || id.isEmpty) {
      throw const FormatException('GroupBan: Missing required field "id"');
    }
    if (groupId.isEmpty || userId.isEmpty) {
      throw const FormatException('GroupBan: Missing required user/group id');
    }

    return GroupBan(
      id: id,
      groupId: groupId,
      userId: userId,
      username: json.getString('username'),
      email: json.getString('email'),
      avatarUrl: json.getString('avatar_url', 'avatarUrl'),
      reason: json.getString('reason'),
      bannedBy: json.getString('banned_by', 'bannedBy'),
      createdAt: json.getDateTimeOrNow('created_at', 'createdAt'),
    );
  }
}
