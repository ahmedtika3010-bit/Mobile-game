import 'dart:async';

import 'api.dart';
import 'colyseus.dart';
import 'models.dart';

enum ConnectionStatus { connected, reconnecting, lost }

/// One player's live connection to a game room: views, server clock offset,
/// answers, and automatic reconnection inside the server's 90-second window.
class GameSession {
  GameSession._(this._client, this._room);

  final ColyseusClient _client;
  ColyseusRoom _room;
  StreamSubscription<RoomMessage>? _sub;
  bool _leaving = false;

  final _views = StreamController<RoomView>.broadcast();
  final _summaries = StreamController<MatchSummary>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  final _chat = StreamController<({String from, String phraseId})>.broadcast();

  /// Draw and Guess: the current drawing's operations, kept in sync from the
  /// room's stream (only new operations arrive; a new key starts over).
  final canvas = DrawCanvas();

  RoomView? view;
  MatchSummary? lastSummary;
  ConnectionStatus status = ConnectionStatus.connected;

  /// serverTime - localTime, estimated from ping round trips.
  int clockOffsetMs = 0;
  int? _shownAtLocal; // when the current question became visible on this device
  int? _shownIndex;

  /// Emits the latest view first (if any), then every new one.
  Stream<RoomView> get views => _replay(_views.stream, view);
  Stream<MatchSummary> get summaries => _replay(_summaries.stream, lastSummary);

  static Stream<T> _replay<T>(Stream<T> source, T? latest) =>
      Stream<T>.multi((c) {
        if (latest != null) c.add(latest);
        final sub = source.listen(c.add, onError: c.addError, onDone: c.close);
        c.onCancel = sub.cancel;
      });
  Stream<String> get errors => _errors.stream;
  Stream<ConnectionStatus> get statusChanges => _status.stream;
  Stream<({String from, String phraseId})> get quickChat => _chat.stream;
  String get roomId => _room.roomId;

  static const reconnectWindow = Duration(seconds: 90);

  static Future<GameSession> quickPlay(SahraApi api, ColyseusClient client,
      {required String gameId, required String mode}) async {
    final t = await api.ticket(gameId, mode);
    return _start(client, await client.joinOrCreate('game', t.joinOptions));
  }

  static Future<GameSession> createPrivate(SahraApi api, ColyseusClient client,
      {required String gameId, Map<String, dynamic>? config}) async {
    final t = await api.ticket(gameId, 'private');
    return _start(
        client,
        await client.create(
            'game', {...t.joinOptions, if (config != null) 'config': config}));
  }

  /// One player against labelled bots. Starts by itself; no rewards.
  static Future<GameSession> practice(SahraApi api, ColyseusClient client,
      {required String gameId, Map<String, dynamic>? config}) async {
    final t = await api.ticket(gameId, 'practice');
    return _start(
        client,
        await client.create(
            'game', {...t.joinOptions, if (config != null) 'config': config}));
  }

  static Future<GameSession> joinByCode(SahraApi api, ColyseusClient client,
      {required String gameId, required String code}) async {
    final room = await api.roomForCode(code);
    final t = await api.ticket(room.gameId ?? gameId, 'private');
    return _start(
        client, await client.joinById(room.roomId, {'ticket': t.ticket}));
  }

  static GameSession _start(ColyseusClient client, ColyseusRoom room) {
    final s = GameSession._(client, room);
    s._attach();
    s.syncClock();
    return s;
  }

  int get serverNow => DateTime.now().millisecondsSinceEpoch + clockOffsetMs;

  void _attach() {
    _sub?.cancel();
    _sub = _room.messages.listen(_onMessage);
    _room.closed.then((code) {
      // 4000 = consented leave. Anything else is an interruption worth retrying.
      if (!_leaving && code != 4000) _reconnect();
    });
  }

  void _onMessage(RoomMessage m) {
    switch (m.type) {
      case 'view':
        final v = RoomView.fromJson((m.payload as Map).cast());
        final q = v.quiz?.question;
        if (q != null && q.index != _shownIndex) {
          _shownIndex = q.index;
          _shownAtLocal = null;
        }
        view = v;
        _views.add(v);
      case 'matchSummary':
        lastSummary = MatchSummary.fromJson(
            ((m.payload as Map)['summary'] as Map).cast());
        _summaries.add(lastSummary!);
      case 'pong':
        final p = (m.payload as Map).cast<String, dynamic>();
        final now = DateTime.now().millisecondsSinceEpoch;
        final sent = (p['clientTime'] as num).toInt();
        final server = (p['serverTime'] as num).toInt();
        clockOffsetMs = server - (sent + (now - sent) ~/ 2);
      case 'stream':
        final p = (m.payload as Map).cast<String, dynamic>();
        final ok = canvas.apply(p['key'] as String, (p['from'] as num).toInt(),
            (p['items'] as List).cast<Object?>());
        if (!ok) _room.send('resync', {});
      case 'quickChat':
        final p = (m.payload as Map).cast<String, dynamic>();
        _chat.add(
            (from: p['from'] as String, phraseId: p['phraseId'] as String));
      case 'error':
      case '__error':
        _errors.add('${(m.payload as Map)['code']}');
    }
  }

  void syncClock() =>
      _room.send('ping', {'clientTime': DateTime.now().millisecondsSinceEpoch});

  /// The UI calls this when the question is actually painted on screen.
  void markQuestionShown(int index) {
    if (_shownIndex == index && _shownAtLocal == null) {
      _shownAtLocal = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Guess with Emoji, typed mode: sends a typed guess for the puzzle.
  void guess(int questionIndex, String text) {
    final shown = _shownAtLocal;
    final elapsed =
        shown == null ? null : DateTime.now().millisecondsSinceEpoch - shown;
    _room.send('action', {
      'action': {
        'kind': 'guess',
        'questionIndex': questionIndex,
        'text': text,
        if (elapsed != null) 'clientElapsedMs': elapsed
      },
    });
  }

  void answer(int questionIndex, int choice) {
    final shown = _shownAtLocal;
    final elapsed =
        shown == null ? null : DateTime.now().millisecondsSinceEpoch - shown;
    _room.send('action', {
      'action': {
        'kind': 'answer',
        'questionIndex': questionIndex,
        'choice': choice,
        if (elapsed != null) 'clientElapsedMs': elapsed
      },
    });
  }

  /// Sends a game action as-is (games other than the quiz).
  void action(Map<String, dynamic> action) =>
      _room.send('action', {'action': action});

  // Spy
  void spyAsk(int turn, int question, String target) => action(
      {'kind': 'ask', 'turn': turn, 'question': question, 'target': target});
  void spyAnswer(int turn, int answer) =>
      action({'kind': 'answer', 'turn': turn, 'answer': answer});
  void spySuspect(String? target) =>
      action({'kind': 'suspect', 'target': target});
  void spyReadyToVote() => action({'kind': 'readyToVote'});
  void spyVote(String target) => action({'kind': 'vote', 'target': target});
  void spyGuess(int choice) => action({'kind': 'guess', 'choice': choice});

  // Who Is the Liar? (suspect / ready / vote share the Spy actions' shape)
  void liarAnswer(int round, int choice) =>
      action({'kind': 'answer', 'round': round, 'choice': choice});

  // Who Among Us?
  void whoVote(int question, String target) =>
      action({'kind': 'vote', 'question': question, 'target': target});
  void whoSkip(int question) => action({'kind': 'skip', 'question': question});

  /// Stop: saves your whole sheet (send again after each edit).
  void stopAnswers(int round, Map<String, String> answers,
          {bool done = false}) =>
      action({
        'kind': 'answers',
        'round': round,
        'answers': answers,
        if (done) 'done': true
      });
  void stopAppeal(int round, String category) =>
      action({'kind': 'appeal', 'round': round, 'category': category});

  /// Memory: one pick (cards: next target's cell; spot: the changed cell).
  void memoryPick(int round, int cell) => action({
        'kind': 'pick',
        'round': round,
        'cell': cell,
        if (_answerOpenedLocal != null)
          'clientElapsedMs':
              DateTime.now().millisecondsSinceEpoch - _answerOpenedLocal!
      });

  /// Memory, sequence mode: the whole order.
  void memorySequence(int round, List<int> items) => action({
        'kind': 'sequence',
        'round': round,
        'items': items,
        if (_answerOpenedLocal != null)
          'clientElapsedMs':
              DateTime.now().millisecondsSinceEpoch - _answerOpenedLocal!
      });

  int? _answerOpenedLocal;

  /// Memory: call when the answer board appears on screen (for latency compensation).
  void markAnswerOpened() =>
      _answerOpenedLocal = DateTime.now().millisecondsSinceEpoch;

  // Draw and Guess
  void drawChoose(int turn, int choice) =>
      action({'kind': 'choose', 'turn': turn, 'choice': choice});

  /// Sends drawing operations (see DrawCanvas for their shape).
  void drawOps(int turn, List<Map<String, Object>> ops) =>
      action({'kind': 'draw', 'turn': turn, 'ops': ops});
  void drawGuess(int turn, String text, {int? elapsedMs}) => action({
        'kind': 'guess',
        'turn': turn,
        'text': text,
        if (elapsedMs != null) 'clientElapsedMs': elapsedMs
      });
  void drawHide(int turn) => action({'kind': 'hide', 'turn': turn});

  // Acting and Guessing
  void actChoose(int turn, int choice) =>
      action({'kind': 'choose', 'turn': turn, 'choice': choice});
  void actMove(int turn, String move) =>
      action({'kind': 'move', 'turn': turn, 'move': move});
  void actCard(int turn, int card) =>
      action({'kind': 'card', 'turn': turn, 'card': card});
  void actGuess(int turn, String text, {int? elapsedMs}) => action({
        'kind': 'guess',
        'turn': turn,
        'text': text,
        if (elapsedMs != null) 'clientElapsedMs': elapsedMs
      });

  void setReady(bool ready) => _room.send('ready', {'ready': ready});
  void start() => _room.send('start', {});

  // Game Night
  void nightVote(String gameId) => _room.send('nightVote', {'gameId': gameId});
  void nightPick(String gameId) => _room.send('nightPick', {'gameId': gameId});
  void nightPlaylist(List<String> games) =>
      _room.send('nightPlaylist', {'games': games});
  void nightEnd() => _room.send('nightEnd', {});
  void nightNew() => _room.send('nightNew', {});
  void sendPhrase(String phraseId) =>
      _room.send('quickChat', {'phraseId': phraseId});

  Future<void> _reconnect() async {
    final token = _room.reconnectionToken;
    if (token == null) return _setStatus(ConnectionStatus.lost);
    _setStatus(ConnectionStatus.reconnecting);
    final deadline = DateTime.now().add(reconnectWindow);
    var delay = const Duration(milliseconds: 500);
    while (!_leaving && DateTime.now().isBefore(deadline)) {
      try {
        _room = await _client.reconnect(token);
        // The room resends the whole drawing after a reconnection.
        canvas.reset();
        _attach();
        syncClock();
        _setStatus(ConnectionStatus.connected);
        return;
      } catch (_) {
        await Future<void>.delayed(delay);
        delay =
            Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 5000));
      }
    }
    _setStatus(ConnectionStatus.lost);
  }

  void _setStatus(ConnectionStatus s) {
    status = s;
    _status.add(s);
  }

  /// Simulates a network drop (tests and debug menu only).
  Future<void> debugDropConnection() => _room.dropConnection();

  Future<void> leave() async {
    _leaving = true;
    await _room.leave();
    await _sub?.cancel();
  }
}

/// The shared drawing as an append-only list of operations:
/// {t:'b', c, w, p} begins a stroke, {t:'p', p} adds points to it,
/// {t:'u'} undoes the last stroke, {t:'x'} clears. Points are flat
/// [x0, y0, x1, y1, ...] in 0..1000.
class DrawCanvas {
  String key = '';
  final List<Map<String, dynamic>> ops = [];
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  /// Applies a stream chunk; false when a chunk was missed (ask to resync).
  bool apply(String k, int from, List<Object?> items) {
    if (k != key || from == 0) {
      // A new drawing, or the whole current one sent again.
      key = k;
      ops.clear();
    }
    if (from != ops.length) {
      _changes.add(null);
      return false;
    }
    for (final i in items) {
      ops.add((i as Map).cast<String, dynamic>());
    }
    _changes.add(null);
    return true;
  }

  void reset() {
    key = '';
    ops.clear();
    _changes.add(null);
  }

  /// The strokes to paint after applying undo and clear.
  static List<DrawStroke> strokesOf(Iterable<Map<String, dynamic>> ops) {
    final out = <DrawStroke>[];
    for (final op in ops) {
      switch (op['t']) {
        case 'b':
          out.add(DrawStroke((op['c'] as num).toInt(), (op['w'] as num).toInt(),
              [for (final n in op['p'] as List) (n as num).toDouble()]));
        case 'p':
          if (out.isNotEmpty) {
            out.last.points.addAll(
                [for (final n in op['p'] as List) (n as num).toDouble()]);
          }
        case 'u':
          if (out.isNotEmpty) out.removeLast();
        case 'x':
          out.clear();
      }
    }
    return out;
  }
}

class DrawStroke {
  DrawStroke(this.color, this.width, this.points);
  final int color;
  final int width;

  /// Flat x, y pairs in 0..1000.
  final List<double> points;
}
