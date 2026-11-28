/// Game Night (سهرة اللعب). Mirrors packages/shared/src/night.ts.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Same as NIGHT_ID: the ticket "game" for a Game Night room.
const nightId = 'night';

class NightStanding {
  NightStanding.fromJson(Map<String, dynamic> j)
      : playerId = j['playerId'] as String,
        points = _int(j['points']),
        wins = _int(j['wins']),
        played = _int(j['played']);
  final String playerId;
  final int points;
  final int wins;
  final int played;
}

class NightGamePlayed {
  NightGamePlayed.fromJson(Map<String, dynamic> j)
      : gameId = j['gameId'] as String,
        winners = ((j['winners'] as List?) ?? const []).cast<String>();
  final String gameId;
  final List<String> winners;
}

class NightVote {
  NightVote.fromJson(Map<String, dynamic> j)
      : endsAt = _int(j['endsAt']),
        options = {
          for (final o in (j['options'] as List))
            (o as Map)['gameId'] as String: _int(o['votes'])
        },
        yourVote = j['yourVote'] as String?,
        voted = _int(j['voted']),
        voters = _int(j['voters']),
        tie = (j['tie'] as List?)?.cast<String>(),
        tieEndsAt = j['tieEndsAt'] == null ? null : _int(j['tieEndsAt']);
  final int endsAt;

  /// gameId -> votes, in the server's order.
  final Map<String, int> options;
  final String? yourVote;
  final int voted;
  final int voters;
  final List<String>? tie;
  final int? tieEndsAt;
}

class NightSummary {
  NightSummary.fromJson(Map<String, dynamic> j)
      : standings = NightView._standings(j['standings']),
        played = NightView._played(j['played']),
        durationSec = _int(j['durationSec']),
        titles = {
          for (final t in (j['titles'] as List? ?? const []))
            (t as Map)['playerId'] as String: t['title'] as String
        };
  final List<NightStanding> standings;
  final List<NightGamePlayed> played;
  final int durationSec;

  /// playerId -> title id (champion, most_wins, steady, good_sport).
  final Map<String, String> titles;
}

class NightView {
  NightView.fromJson(Map<String, dynamic> j)
      : played = _played(j['played']),
        standings = _standings(j['standings']),
        playlist = ((j['playlist'] as List?) ?? const []).cast<String>(),
        eligible = ((j['eligible'] as List?) ?? const []).cast<String>(),
        vote = j['vote'] == null
            ? null
            : NightVote.fromJson((j['vote'] as Map).cast()),
        next = j['next'] as String?,
        summary = j['summary'] == null
            ? null
            : NightSummary.fromJson((j['summary'] as Map).cast()),
        startedAt = _int(j['startedAt']);
  static List<NightStanding> _standings(Object? v) => ((v as List?) ?? const [])
      .map((e) => NightStanding.fromJson((e as Map).cast()))
      .toList();
  static List<NightGamePlayed> _played(Object? v) => ((v as List?) ?? const [])
      .map((e) => NightGamePlayed.fromJson((e as Map).cast()))
      .toList();

  final List<NightGamePlayed> played;
  final List<NightStanding> standings;
  final List<String> playlist;
  final List<String> eligible;
  final NightVote? vote;
  final String? next;
  final NightSummary? summary;
  final int startedAt;
}
