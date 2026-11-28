import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('parses a Game Night view with a tied vote and a summary', () {
    final n = NightView.fromJson({
      'played': [
        {'gameId': 'quiz', 'matchId': 'm1', 'winners': ['a']},
      ],
      'standings': [
        {'playerId': 'a', 'points': 90, 'wins': 1, 'played': 1},
        {'playerId': 'b', 'points': 40, 'wins': 0, 'played': 1},
      ],
      'playlist': ['spy'],
      'eligible': ['quiz', 'spy', 'draw'],
      'vote': {
        'endsAt': 1000,
        'options': [
          {'gameId': 'quiz', 'votes': 1},
          {'gameId': 'spy', 'votes': 1},
        ],
        'yourVote': 'spy',
        'voted': 2,
        'voters': 2,
        'tie': ['quiz', 'spy'],
        'tieEndsAt': 2000,
      },
      'next': null,
      'summary': {
        'standings': [
          {'playerId': 'a', 'points': 90, 'wins': 1, 'played': 1},
        ],
        'played': [],
        'durationSec': 600,
        'titles': [
          {'playerId': 'a', 'title': 'champion'},
        ],
      },
      'startedAt': 5,
    });
    expect(n.standings.first.points, 90);
    expect(n.played.single.winners, ['a']);
    expect(n.vote!.options, {'quiz': 1, 'spy': 1});
    expect(n.vote!.tie, ['quiz', 'spy']);
    expect(n.vote!.yourVote, 'spy');
    expect(n.summary!.titles['a'], 'champion');
    expect(n.summary!.durationSec, 600);
    expect(n.playlist, ['spy']);
  });

  test('a room without Game Night has no night view', () {
    final v = NightView.fromJson({'startedAt': 1});
    expect(v.vote, isNull);
    expect(v.summary, isNull);
    expect(v.standings, isEmpty);
  });
}
