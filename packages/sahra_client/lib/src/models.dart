/// Typed views of the server's JSON messages. Field names match
/// packages/shared/src/protocol.ts and quiz.ts.
library;

class PublicPlayer {
  PublicPlayer.fromJson(Map<String, dynamic> j)
      : playerId = j['playerId'] as String,
        displayName = j['displayName'] as String,
        avatarId = j['avatarId'] as String,
        connected = j['connected'] as bool,
        ready = j['ready'] as bool,
        isHost = j['isHost'] as bool,
        waiting = j['waiting'] as bool,
        isBot = j['isBot'] == true;
  final String playerId;
  final String displayName;
  final String avatarId;
  final bool connected;
  final bool ready;
  final bool isHost;
  final bool waiting;

  /// Practice-mode computer player.
  final bool isBot;
}

class QuizQuestion {
  QuizQuestion.fromJson(Map<String, dynamic> j)
      : index = _int(j['index']),
        total = _int(j['total']),
        category = j['category'] as String,
        prompt = j['prompt'] as String,
        choices = (j['choices'] as List).cast<String>(),
        revealAt = _int(j['revealAt']),
        deadline = _int(j['deadline']);
  final int index;
  final int total;
  final String category;
  final String prompt;
  final List<String> choices;
  final int revealAt;
  final int deadline;
}

class QuizReveal {
  QuizReveal.fromJson(Map<String, dynamic> j)
      : index = _int(j['index']),
        correctChoice = _int(j['correctChoice']),
        explanation = j['explanation'] as String?,
        points = (j['points'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        picks = ((j['picks'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', _int(v)));
  final int index;
  final int correctChoice;
  final String? explanation;
  final Map<String, int> points;

  /// What each player picked, revealed after the question closes.
  final Map<String, int> picks;
}

class RankingEntry {
  RankingEntry.fromJson(Map<String, dynamic> j)
      : playerId = j['playerId'] as String,
        score = _int(j['score']),
        correct = _int(j['correct']),
        place = _int(j['place']);
  final String playerId;
  final int score;
  final int correct;
  final int place;
}

class QuizView {
  QuizView.fromJson(Map<String, dynamic> j)
      : stage = j['stage'] as String,
        question = j['question'] == null
            ? null
            : QuizQuestion.fromJson((j['question'] as Map).cast()),
        yourChoice = j['yourChoice'] == null ? null : _int(j['yourChoice']),
        answeredCount = _int(j['answeredCount']),
        reveal = j['reveal'] == null
            ? null
            : QuizReveal.fromJson((j['reveal'] as Map).cast()),
        scores = (j['scores'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        ranking = j['final'] == null
            ? null
            : ((j['final'] as Map)['ranking'] as List)
                .map((e) => RankingEntry.fromJson((e as Map).cast()))
                .toList();
  final String stage; // question | reveal | finished
  final QuizQuestion? question;
  final int? yourChoice;
  final int answeredCount;
  final QuizReveal? reveal;
  final Map<String, int> scores;
  final List<RankingEntry>? ranking;
}

class RoomView {
  RoomView.fromJson(Map<String, dynamic> j)
      : roomId = j['roomId'] as String,
        code = j['code'] as String?,
        gameId = j['gameId'] as String,
        mode = j['mode'] as String,
        phase = j['phase'] as String,
        commMode = j['commMode'] as String,
        players = (j['players'] as List)
            .map((e) => PublicPlayer.fromJson((e as Map).cast()))
            .toList(),
        you = j['you'] as String,
        serverNow = _int(j['serverNow']),
        countdownEndsAt =
            j['countdownEndsAt'] == null ? null : _int(j['countdownEndsAt']),
        expectedDurationSec = _int(j['expectedDurationSec']),
        quiz = j['game'] == null
            ? null
            : QuizView.fromJson((j['game'] as Map).cast());
  final String roomId;
  final String? code;
  final String gameId;
  final String mode;
  final String phase; // lobby | countdown | playing | results | closed
  final String commMode; // normal | safe
  final List<PublicPlayer> players;
  final String you;
  final int serverNow;
  final int? countdownEndsAt;
  final int expectedDurationSec;
  final QuizView? quiz;

  PublicPlayer? get me => players.where((p) => p.playerId == you).firstOrNull;
  bool get isSafeMode => commMode == 'safe';
}

class MatchSummary {
  MatchSummary.fromJson(Map<String, dynamic> j)
      : matchId = j['matchId'] as String,
        xp = _int(j['xp']),
        coins = _int(j['coins']),
        ratingBefore =
            j['rating'] == null ? null : _int((j['rating'] as Map)['before']),
        ratingAfter =
            j['rating'] == null ? null : _int((j['rating'] as Map)['after']),
        provisional = j['rating'] == null
            ? false
            : (j['rating'] as Map)['provisional'] as bool,
        notes = (j['notes'] as List).cast<String>();
  final String matchId;
  final int xp;
  final int coins;
  final int? ratingBefore;
  final int? ratingAfter;
  final bool provisional;
  final List<String> notes;
}

class UserProfile {
  UserProfile.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        displayName = j['displayName'] as String?,
        avatarId = j['avatarId'] as String,
        ageBand = j['ageBand'] as String,
        onboarded = j['onboarded'] as bool,
        status = j['status'] as String;
  final String id;
  final String? displayName;
  final String avatarId;
  final String ageBand;
  final bool onboarded;
  final String status;
}

int _int(Object? v) => (v as num).toInt();
