import 'package:noteclaw/core/utils/app_logger.dart';

const _logger = AppLogger('Friend');

class Friend {
  final String id;
  final String friendId;
  final String username;
  final String?
      email; // Made optional since backend doesn't return it for privacy
  final String? avatarUrl;
  final String status;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  Friend({
    required this.id,
    required this.friendId,
    required this.username,
    this.email,
    this.avatarUrl,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    try {
      return Friend(
        id: json['id'] as String,
        friendId: (json['friend_id'] ?? json['friendId']) as String,
        username: json['username'] as String,
        email: json['email'] as String?, // Optional
        avatarUrl: (json['avatar_url'] ?? json['avatarUrl']) as String?,
        status: (json['status'] ?? 'accepted') as String,
        createdAt:
            DateTime.parse((json['created_at'] ?? json['createdAt']) as String),
        acceptedAt: (json['accepted_at'] ?? json['acceptedAt']) != null
            ? DateTime.parse(
                (json['accepted_at'] ?? json['acceptedAt']) as String)
            : null,
      );
    } catch (e) {
      _logger.error('Error parsing Friend from JSON', e);
      _logger.debug('JSON data: $json');
      rethrow;
    }
  }
}

class FriendRequest {
  final String id;
  final String fromUserId;
  final String fromUsername;
  final String? fromEmail; // Made optional
  final String? fromAvatarUrl;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.fromUsername,
    this.fromEmail,
    this.fromAvatarUrl,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    try {
      return FriendRequest(
        id: json['id'] as String,
        fromUserId: (json['from_user_id'] ?? json['fromUserId']) as String,
        fromUsername: (json['from_username'] ?? json['fromUsername']) as String,
        fromEmail:
            (json['from_email'] ?? json['fromEmail']) as String?, // Optional
        fromAvatarUrl:
            (json['from_avatar_url'] ?? json['fromAvatarUrl']) as String?,
        createdAt:
            DateTime.parse((json['created_at'] ?? json['createdAt']) as String),
      );
    } catch (e) {
      _logger.error('Error parsing FriendRequest from JSON', e);
      _logger.debug('JSON data: $json');
      rethrow;
    }
  }
}

class UserSearchResult {
  final String id;
  final String username;
  final String? email; // Made optional
  final String? avatarUrl;

  UserSearchResult({
    required this.id,
    required this.username,
    this.email,
    this.avatarUrl,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    try {
      return UserSearchResult(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String?, // Optional
        avatarUrl: (json['avatar_url'] ?? json['avatarUrl']) as String?,
      );
    } catch (e) {
      _logger.error('Error parsing UserSearchResult from JSON', e);
      _logger.debug('JSON data: $json');
      rethrow;
    }
  }
}
