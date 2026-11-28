import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('parses the friends overview and ping', () {
    final o = FriendsOverview.fromJson({
      'code': 'ABCD2345',
      'settings': {'allowFriendRequests': false, 'showPresence': true},
      'friends': [
        {
          'id': 'f1',
          'displayName': 'سارة',
          'avatarId': 'chibi_a',
          'status': 'in_game',
          'gameId': 'draw',
          'since': 5
        }
      ],
      'incoming': [
        {'id': 'f2', 'displayName': 'كريم', 'avatarId': 'chibi_b', 'at': 7}
      ],
      'outgoing': [],
      'invites': [
        {
          'id': 'i1',
          'from': {'id': 'f1', 'displayName': 'سارة', 'avatarId': 'chibi_a'},
          'roomCode': 'QWERTY',
          'gameId': 'draw',
          'expiresAt': 99
        }
      ],
    });
    expect(o.code, 'ABCD2345');
    expect(o.settings.allowFriendRequests, isFalse);
    expect(o.friends.single.status, 'in_game');
    expect(o.friends.single.gameId, 'draw');
    expect(o.incoming.single.status, 'offline');
    expect(o.invites.single.roomCode, 'QWERTY');
    final p = FriendsPing.fromJson({'incoming': 2, 'invites': []});
    expect(p.incoming, 2);
    expect(p.invites, isEmpty);
  });
}
