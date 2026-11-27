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
        deadline = _int(j['deadline']),
        emojis = j['emojis'] as String?,
        mode = (j['mode'] as String?) ?? 'choices',
        hint = j['hint'] as String?;
  final int index;
  final int total;
  final String category;
  final String prompt;
  final List<String> choices;
  final int revealAt;
  final int deadline;

  /// Guess with Emoji: the puzzle, the answer mode and (typed mode, after
  /// half time) the answer's shape.
  final String? emojis;
  final String mode; // choices | typed
  final String? hint;
  bool get typed => mode == 'typed';
}

class QuizReveal {
  QuizReveal.fromJson(Map<String, dynamic> j)
      : index = _int(j['index']),
        correctChoice = _int(j['correctChoice']),
        explanation = j['explanation'] as String?,
        points = (j['points'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        picks = ((j['picks'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', _int(v))),
        answer = j['answer'] as String?;
  final int index;

  /// Guess with Emoji: the approved answer as text.
  final String? answer;
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
        yourGuesses =
            ((j['yourGuesses'] as List?) ?? const []).cast<String>(),
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

  /// Guess with Emoji, typed mode: your own wrong guesses on this puzzle.
  final List<String> yourGuesses;
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
        // Guess with Emoji shares the quiz view shape (and screens).
        quiz = j['game'] == null ||
                (j['gameId'] != 'quiz' && j['gameId'] != 'emoji')
            ? null
            : QuizView.fromJson((j['game'] as Map).cast()),
        spy = j['game'] == null || j['gameId'] != 'spy'
            ? null
            : SpyView.fromJson((j['game'] as Map).cast()),
        liar = j['game'] == null || j['gameId'] != 'liar'
            ? null
            : LiarView.fromJson((j['game'] as Map).cast()),
        who = j['game'] == null || j['gameId'] != 'who'
            ? null
            : WhoView.fromJson((j['game'] as Map).cast()),
        stop = j['game'] == null || j['gameId'] != 'stop'
            ? null
            : StopView.fromJson((j['game'] as Map).cast());
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
  final SpyView? spy;
  final LiarView? liar;
  final WhoView? who;
  final StopView? stop;

  PublicPlayer? get me => players.where((p) => p.playerId == you).firstOrNull;
  bool get isSafeMode => commMode == 'safe';
}

/// Spy (الجاسوس). See packages/shared/src/spy.ts.
class SpyTurn {
  SpyTurn.fromJson(Map<String, dynamic> j)
      : index = _int(j['index']),
        total = _int(j['total']),
        asker = j['asker'] as String,
        target = j['target'] as String?,
        questionOptions = (j['questionOptions'] as List?)?.cast<String>(),
        question = j['question'] as String?,
        answer = j['answer'] == null ? null : _int(j['answer']);
  final int index;
  final int total;
  final String asker;
  final String? target;
  final List<String>? questionOptions;
  final String? question;
  final int? answer;
}

class SpyHistoryEntry {
  SpyHistoryEntry.fromJson(Map<String, dynamic> j)
      : asker = j['asker'] as String,
        target = j['target'] as String,
        question = j['question'] as String,
        answer = j['answer'] == null ? null : _int(j['answer']);
  final String asker;
  final String target;
  final String question;
  final int? answer;
}

class SpyFinal {
  SpyFinal.fromJson(Map<String, dynamic> j)
      : winner = j['winner'] as String,
        reason = j['reason'] as String,
        spies = (j['spies'] as List).cast<String>(),
        word = j['word'] as String,
        voteCounts =
            (j['voteCounts'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        accused = j['accused'] as String?,
        guessedWord = j['guessedWord'] as String?,
        ranking = (j['ranking'] as List)
            .map((e) => RankingEntry.fromJson(
                {...(e as Map).cast<String, dynamic>(), 'correct': 0}))
            .toList();
  final String winner; // spies | citizens
  final String reason;
  final List<String> spies;
  final String word;
  final Map<String, int> voteCounts;
  final String? accused;
  final String? guessedWord;
  final List<RankingEntry> ranking;
}

class SpyView {
  SpyView.fromJson(Map<String, dynamic> j)
      : stage = j['stage'] as String,
        stageEndsAt = _int(j['stageEndsAt']),
        category = j['category'] as String,
        role = j['role'] as String?,
        word = j['word'] as String?,
        spyCount = _int(j['spyCount']),
        turn = j['turn'] == null
            ? null
            : SpyTurn.fromJson((j['turn'] as Map).cast()),
        history = (j['history'] as List)
            .map((e) => SpyHistoryEntry.fromJson((e as Map).cast()))
            .toList(),
        suspicions =
            (j['suspicions'] as Map).map((k, v) => MapEntry('$k', v as String)),
        readyCount = _int(j['readyCount']),
        youReady = j['youReady'] == true,
        yourVote = j['yourVote'] as String?,
        votedCount = _int(j['votedCount']),
        guessOptions = (j['guessOptions'] as List?)?.cast<String>(),
        guesser = j['guesser'] as String?,
        final_ = j['final'] == null
            ? null
            : SpyFinal.fromJson((j['final'] as Map).cast());

  /// roles | ask | answer | discuss | vote | guess | finished
  final String stage;
  final int stageEndsAt;
  final String category;
  final String? role; // spy | citizen
  final String? word;
  final int spyCount;
  final SpyTurn? turn;
  final List<SpyHistoryEntry> history;
  final Map<String, String> suspicions;
  final int readyCount;
  final bool youReady;
  final String? yourVote;
  final int votedCount;
  final List<String>? guessOptions;
  final String? guesser;
  final SpyFinal? final_;

  bool get isSpy => role == 'spy';
}

/// Who Is the Liar? (مين الكداب؟). See packages/shared/src/liar.ts.
class LiarRoundResult {
  LiarRoundResult.fromJson(Map<String, dynamic> j)
      : round = _int(j['round']),
        liar = j['liar'] as String,
        mainQuestion = j['mainQuestion'] as String,
        oddQuestion = j['oddQuestion'] as String,
        voteCounts =
            (j['voteCounts'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        accused = j['accused'] as String?,
        caught = j['caught'] == true,
        points = (j['points'] as Map).map((k, v) => MapEntry('$k', _int(v)));
  final int round;
  final String liar;
  final String mainQuestion;
  final String oddQuestion;
  final Map<String, int> voteCounts;
  final String? accused;
  final bool caught;
  final Map<String, int> points;
}

class LiarFinal {
  LiarFinal.fromJson(Map<String, dynamic> j)
      : rounds = (j['rounds'] as List)
            .map((e) => LiarRoundResult.fromJson((e as Map).cast()))
            .toList(),
        ranking = (j['ranking'] as List)
            .map((e) => RankingEntry.fromJson(
                {...(e as Map).cast<String, dynamic>(), 'correct': 0}))
            .toList();
  final List<LiarRoundResult> rounds;
  final List<RankingEntry> ranking;
}

class LiarView {
  LiarView.fromJson(Map<String, dynamic> j)
      : stage = j['stage'] as String,
        stageEndsAt = _int(j['stageEndsAt']),
        round = _int(j['round']),
        rounds = _int(j['rounds']),
        difficulty = j['difficulty'] as String,
        yourQuestion = j['yourQuestion'] as String?,
        mainQuestion = j['mainQuestion'] as String?,
        options = (j['options'] as List).cast<String>(),
        yourAnswer = j['yourAnswer'] == null ? null : _int(j['yourAnswer']),
        answeredCount = _int(j['answeredCount']),
        answers = (j['answers'] as Map?)
            ?.map((k, v) => MapEntry('$k', v == null ? null : _int(v))),
        youAreLiar = j['youAreLiar'] as bool?,
        suspicions =
            (j['suspicions'] as Map).map((k, v) => MapEntry('$k', v as String)),
        readyCount = _int(j['readyCount']),
        youReady = j['youReady'] == true,
        yourVote = j['yourVote'] as String?,
        votedCount = _int(j['votedCount']),
        scores = (j['scores'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        lastRound = j['lastRound'] == null
            ? null
            : LiarRoundResult.fromJson((j['lastRound'] as Map).cast()),
        final_ = j['final'] == null
            ? null
            : LiarFinal.fromJson((j['final'] as Map).cast());

  /// answer | discuss | vote | roundEnd | finished
  final String stage;
  final int stageEndsAt;
  final int round;
  final int rounds;
  final String difficulty;
  final String? yourQuestion;
  final String? mainQuestion;
  final List<String> options;
  final int? yourAnswer;
  final int answeredCount;
  final Map<String, int?>? answers;
  final bool? youAreLiar;
  final Map<String, String> suspicions;
  final int readyCount;
  final bool youReady;
  final String? yourVote;
  final int votedCount;
  final Map<String, int> scores;
  final LiarRoundResult? lastRound;
  final LiarFinal? final_;
}

/// Stop / Atobees Complete (أتوبيس كومبليت). See packages/shared/src/stop.ts.
class StopCell {
  StopCell.fromJson(Map<String, dynamic> j)
      : verdict = j['verdict'] as String,
        text = j['text'] as String?,
        points = _int(j['points']),
        appealed = j['appealed'] == true;

  /// unique | shared | wrong_letter | unknown | empty
  final String verdict;

  /// Null when hidden from you (someone else's word the dictionary did not know).
  final String? text;
  final int points;
  final bool appealed;
}

class StopRoundResult {
  StopRoundResult.fromJson(Map<String, dynamic> j)
      : round = _int(j['round']),
        letter = j['letter'] as String,
        cells = (j['cells'] as Map).map((c, row) => MapEntry(
            '$c',
            (row as Map).map((p, cell) => MapEntry(
                '$p', StopCell.fromJson((cell as Map).cast()))))),
        points = (j['points'] as Map).map((k, v) => MapEntry('$k', _int(v)));
  final int round;
  final String letter;

  /// category -> playerId -> cell
  final Map<String, Map<String, StopCell>> cells;
  final Map<String, int> points;
}

class StopFinal {
  StopFinal.fromJson(Map<String, dynamic> j)
      : rounds = (j['rounds'] as List)
            .map((e) => (
                  round: _int((e as Map)['round']),
                  letter: e['letter'] as String,
                  points: (e['points'] as Map)
                      .map((k, v) => MapEntry('$k', _int(v)))
                ))
            .toList(),
        ranking = (j['ranking'] as List)
            .map((e) => RankingEntry.fromJson((e as Map).cast()))
            .toList();
  final List<({int round, String letter, Map<String, int> points})> rounds;
  final List<RankingEntry> ranking;
}

class StopView {
  StopView.fromJson(Map<String, dynamic> j)
      : stage = j['stage'] as String,
        stageEndsAt = _int(j['stageEndsAt']),
        round = _int(j['round']),
        totalRounds = _int(j['totalRounds']),
        letter = j['letter'] as String?,
        categories = (j['categories'] as List).cast<String>(),
        yourAnswers = ((j['yourAnswers'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', v as String)),
        youDone = j['youDone'] == true,
        doneCount = _int(j['doneCount']),
        result = j['result'] == null
            ? null
            : StopRoundResult.fromJson((j['result'] as Map).cast()),
        scores = (j['scores'] as Map).map((k, v) => MapEntry('$k', _int(v))),
        final_ = j['final'] == null
            ? null
            : StopFinal.fromJson((j['final'] as Map).cast());

  /// answer | review | finished
  final String stage;
  final int stageEndsAt;
  final int round;
  final int totalRounds;
  final String? letter;
  final List<String> categories;
  final Map<String, String> yourAnswers;
  final bool youDone;
  final int doneCount;
  final StopRoundResult? result;
  final Map<String, int> scores;
  final StopFinal? final_;
}

/// Who Among Us? (مين فينا؟). See packages/shared/src/who.ts.
class WhoReveal {
  WhoReveal.fromJson(Map<String, dynamic> j)
      : kind = j['kind'] as String,
        picks = (j['picks'] as List).cast<String>(),
        votes = _int(j['votes']),
        counts = (j['counts'] as Map?)?.map((k, v) => MapEntry('$k', _int(v)));

  /// pick | too_few | spread
  final String kind;
  final List<String> picks;
  final int votes;
  final Map<String, int>? counts;
}

class WhoFinal {
  WhoFinal.fromJson(Map<String, dynamic> j)
      : questions = _int(j['questions']),
        votesCast = _int(j['votesCast']),
        skips = _int(j['skips']),
        titles =
            (j['titles'] as Map).map((k, v) => MapEntry('$k', v as String)),
        highlights = (j['highlights'] as List)
            .map((e) => (
                  text: (e as Map)['text'] as String,
                  picks: (e['picks'] as List).cast<String>()
                ))
            .toList();
  final int questions;
  final int votesCast;
  final int skips;
  final Map<String, String> titles;
  final List<({String text, List<String> picks})> highlights;
}

class WhoView {
  WhoView.fromJson(Map<String, dynamic> j)
      : stage = j['stage'] as String,
        stageEndsAt = _int(j['stageEndsAt']),
        index = _int(j['index']),
        total = _int(j['total']),
        questionText = (j['question'] as Map?)?['text'] as String?,
        category = (j['question'] as Map?)?['category'] as String?,
        yourChoice = j['yourChoice'] as String?,
        answeredCount = _int(j['answeredCount']),
        reveal = j['reveal'] == null
            ? null
            : WhoReveal.fromJson((j['reveal'] as Map).cast()),
        final_ = j['final'] == null
            ? null
            : WhoFinal.fromJson((j['final'] as Map).cast());

  /// vote | reveal | finished
  final String stage;
  final int stageEndsAt;
  final int index;
  final int total;
  final String? questionText;
  final String? category;
  final String? yourChoice;
  final int answeredCount;
  final WhoReveal? reveal;
  final WhoFinal? final_;
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
