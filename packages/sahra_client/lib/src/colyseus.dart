/// Minimal Colyseus 0.16 client for message-based rooms (no schema state).
///
/// Wire format (binary WebSocket frames):
///   JOIN_ROOM (10): [10, len, reconnectionToken, len, serializerId, ...] -> reply [10]
///   ERROR (11):     [11, msgpack(code), msgpack(message)]
///   LEAVE_ROOM (12): client sends [12] to leave on purpose
///   ROOM_DATA (13): [13, msgpack(type), msgpack(payload)?]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'msgpack.dart';

class MatchmakeException implements Exception {
  MatchmakeException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'MatchmakeException($code, $message)';
}

class SeatReservation {
  SeatReservation(this.sessionId, this.roomId, this.processId, this.reconnectionToken);
  final String sessionId;
  final String roomId;
  final String processId;
  final String? reconnectionToken;
}

class ColyseusClient {
  ColyseusClient(this.baseUrl, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  /// e.g. http://10.0.2.2:2567
  final Uri baseUrl;
  final http.Client _http;

  Future<ColyseusRoom> joinOrCreate(String roomName, Map<String, dynamic> options) =>
      _matchmake('joinOrCreate/$roomName', options);
  Future<ColyseusRoom> create(String roomName, Map<String, dynamic> options) =>
      _matchmake('create/$roomName', options);
  Future<ColyseusRoom> joinById(String roomId, Map<String, dynamic> options) =>
      _matchmake('joinById/$roomId', options);

  /// [token] is `ColyseusRoom.reconnectionToken` ("roomId:token").
  Future<ColyseusRoom> reconnect(String token) {
    final i = token.indexOf(':');
    if (i <= 0) throw ArgumentError('bad reconnection token');
    final roomId = token.substring(0, i);
    final secret = token.substring(i + 1);
    return _matchmake('reconnect/$roomId', {'reconnectionToken': secret}, reconnectionToken: secret);
  }

  Future<ColyseusRoom> _matchmake(String path, Map<String, dynamic> options, {String? reconnectionToken}) async {
    final res = await _http.post(
      baseUrl.resolve('/matchmake/$path'),
      headers: {'content-type': 'application/json', 'accept': 'application/json'},
      body: jsonEncode(options),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw MatchmakeException((body['code'] as num?)?.toInt() ?? res.statusCode, '${body['error']}');
    }
    final room = body['room'] as Map<String, dynamic>;
    final seat = SeatReservation(
      body['sessionId'] as String,
      room['roomId'] as String,
      room['processId'] as String,
      reconnectionToken,
    );
    return ColyseusRoom._connect(baseUrl, seat);
  }
}

class RoomMessage {
  RoomMessage(this.type, this.payload);
  final String type;
  final dynamic payload;
}

class ColyseusRoom {
  ColyseusRoom._(this.roomId, this.sessionId, this._channel);

  final String roomId;
  final String sessionId;
  final WebSocketChannel _channel;
  String? reconnectionToken;
  final _messages = StreamController<RoomMessage>.broadcast();
  final _closed = Completer<int?>();

  Stream<RoomMessage> get messages => _messages.stream;

  /// Completes with the close code when the connection ends.
  Future<int?> get closed => _closed.future;

  static Future<ColyseusRoom> _connect(Uri base, SeatReservation seat) async {
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final query = {
      'sessionId': seat.sessionId,
      if (seat.reconnectionToken != null) 'reconnectionToken': seat.reconnectionToken!,
    };
    final url = base.replace(scheme: scheme, path: '/${seat.processId}/${seat.roomId}', queryParameters: query);
    final channel = WebSocketChannel.connect(url);
    final room = ColyseusRoom._(seat.roomId, seat.sessionId, channel);
    final joined = Completer<void>();
    channel.stream.listen(
      (data) {
        final bytes = data is Uint8List ? data : Uint8List.fromList((data as List).cast<int>());
        room._onFrame(bytes, joined);
      },
      onDone: () {
        if (!joined.isCompleted) joined.completeError(MatchmakeException(channel.closeCode ?? 0, channel.closeReason ?? 'closed'));
        if (!room._closed.isCompleted) room._closed.complete(channel.closeCode);
        room._messages.close();
      },
      onError: (Object e) {
        if (!joined.isCompleted) joined.completeError(e);
      },
    );
    await joined.future.timeout(const Duration(seconds: 15));
    return room;
  }

  void _onFrame(Uint8List b, Completer<void> joined) {
    if (b.isEmpty) return;
    switch (b[0]) {
      case 10: // JOIN_ROOM
        var o = 1;
        final tokenLen = b[o++];
        final token = utf8.decode(b.sublist(o, o + tokenLen));
        reconnectionToken = '$roomId:$token';
        _channel.sink.add(Uint8List.fromList([10]));
        if (!joined.isCompleted) joined.complete();
      case 11: // ERROR
        final r = MsgPackReader(b, 1);
        final code = (r.read() as num?)?.toInt() ?? 0;
        final message = '${r.read()}';
        _messages.add(RoomMessage('__error', {'code': code, 'message': message}));
      case 13: // ROOM_DATA
        final r = MsgPackReader(b, 1);
        final type = '${r.read()}';
        final payload = r.hasMore ? r.read() : null;
        _messages.add(RoomMessage(type, payload));
      default:
        break; // state frames are not used by this server
    }
  }

  void send(String type, [Object? payload]) {
    final w = MsgPackWriter()..writeByte(13)..write(type);
    if (payload != null) w.write(payload);
    _channel.sink.add(w.takeBytes());
  }

  /// Leaves on purpose (counts as a confirmed departure during a match).
  Future<void> leave() async {
    _channel.sink.add(Uint8List.fromList([12]));
    await _channel.sink.close();
  }

  /// Drops the connection without leaving (used to test reconnection).
  Future<void> dropConnection() => _channel.sink.close(3000);
}
