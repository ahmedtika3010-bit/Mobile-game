/// Friends: the list, requests, presence and room invitations.
/// Mirrors apps/server/src/http/friends.ts.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class FriendPlayer {
  FriendPlayer.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        displayName = j['displayName'] as String? ?? '',
        avatarId = j['avatarId'] as String? ?? '',
        status = j['status'] as String? ?? 'offline',
        gameId = j['gameId'] as String?,
        at = _int(j['at'] ?? j['since']);
  final String id;
  final String displayName;
  final String avatarId;

  /// online | in_game | offline (friends only; requests are always offline)
  final String status;

  /// The game a friend is in, when status is in_game.
  final String? gameId;
  final int at;
}

class FriendInvite {
  FriendInvite.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        from = FriendPlayer.fromJson((j['from'] as Map).cast()),
        roomCode = j['roomCode'] as String,
        gameId = j['gameId'] as String? ?? '',
        expiresAt = _int(j['expiresAt']);
  final String id;
  final FriendPlayer from;
  final String roomCode;
  final String gameId;
  final int expiresAt;
}

class FriendsSettings {
  const FriendsSettings(
      {required this.allowFriendRequests, required this.showPresence});
  FriendsSettings.fromJson(Map<String, dynamic> j)
      : allowFriendRequests = j['allowFriendRequests'] != false,
        showPresence = j['showPresence'] != false;
  final bool allowFriendRequests;
  final bool showPresence;
}

class FriendsOverview {
  FriendsOverview.fromJson(Map<String, dynamic> j)
      : code = j['code'] as String?,
        settings = FriendsSettings.fromJson((j['settings'] as Map).cast()),
        friends = _list(j['friends']),
        incoming = _list(j['incoming']),
        outgoing = _list(j['outgoing']),
        invites = ((j['invites'] as List?) ?? const [])
            .map((e) => FriendInvite.fromJson((e as Map).cast()))
            .toList();
  static List<FriendPlayer> _list(Object? v) => ((v as List?) ?? const [])
      .map((e) => FriendPlayer.fromJson((e as Map).cast()))
      .toList();

  /// Your friend code (null until your account is fully set up).
  final String? code;
  final FriendsSettings settings;
  final List<FriendPlayer> friends;
  final List<FriendPlayer> incoming;
  final List<FriendPlayer> outgoing;
  final List<FriendInvite> invites;
}

class FriendsPing {
  FriendsPing.fromJson(Map<String, dynamic> j)
      : incoming = _int(j['incoming']),
        invites = ((j['invites'] as List?) ?? const [])
            .map((e) => FriendInvite.fromJson((e as Map).cast()))
            .toList();
  final int incoming;
  final List<FriendInvite> invites;
}
