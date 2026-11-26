import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'ApiException($status, $code)';
}

/// Where tokens are kept. The app plugs in secure storage; tests use memory.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class MemoryTokenStore implements TokenStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? _m.remove(key) : _m[key] = value;
}

class TicketResponse {
  TicketResponse(this.ticket, this.options);
  final String ticket;
  final Map<String, dynamic> options;
  Map<String, dynamic> get joinOptions => {...options, 'ticket': ticket};
}

class SahraApi {
  SahraApi(this.baseUrl, {TokenStore? store, http.Client? client})
      : store = store ?? MemoryTokenStore(),
        _http = client ?? http.Client();

  final Uri baseUrl;
  final TokenStore store;
  final http.Client _http;

  Future<bool> get isSignedIn async => (await store.read('refresh')) != null;

  Future<dynamic> _call(String method, String path,
      {Object? body, bool auth = true, bool retried = false}) async {
    final headers = {'content-type': 'application/json'};
    if (auth) {
      final token = await store.read('access');
      if (token != null) headers['authorization'] = 'Bearer $token';
    }
    final req = http.Request(method, baseUrl.resolve(path))
      ..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    final text = utf8.decode(res.bodyBytes);
    final json = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode == 401 && auth && !retried && await _refresh()) {
      return _call(method, path, body: body, auth: auth, retried: true);
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode,
          json is Map ? '${json['error']}' : 'http_${res.statusCode}');
    }
    return json;
  }

  Future<bool> _refresh() async {
    final refresh = await store.read('refresh');
    if (refresh == null) return false;
    try {
      final j = await _call('POST', '/auth/refresh',
          body: {'refreshToken': refresh}, auth: false) as Map;
      await store.write('access', j['accessToken'] as String);
      await store.write('refresh', j['refreshToken'] as String);
      return true;
    } on ApiException {
      await signOut();
      return false;
    }
  }

  Future<UserProfile> _signIn(String path, Map<String, dynamic> body) async {
    final j = await _call('POST', path, body: body, auth: false) as Map;
    await store.write('access', j['accessToken'] as String);
    await store.write('refresh', j['refreshToken'] as String);
    return UserProfile.fromJson((j['user'] as Map).cast());
  }

  Future<UserProfile> signInWithGoogle(String idToken) =>
      _signIn('/auth/google', {'idToken': idToken});
  Future<UserProfile> signInWithApple(String idToken) =>
      _signIn('/auth/apple', {'idToken': idToken});

  /// Closed test: an invite code shared with friends plus a random key that
  /// stays on this device (the same device always gets the same account).
  Future<UserProfile> signInTester(String code, String deviceKey) =>
      _signIn('/auth/tester', {'code': code, 'deviceKey': deviceKey});

  /// Development builds only; the server refuses it in production.
  Future<UserProfile> signInDev(String subject) =>
      _signIn('/auth/dev', {'subject': subject});

  Future<void> signOut() async {
    await store.write('access', null);
    await store.write('refresh', null);
  }

  Future<String?> accessToken() => store.read('access');

  Future<UserProfile> me() async => UserProfile.fromJson(
      ((await _call('GET', '/me')) as Map)['user'].cast<String, dynamic>());

  Future<UserProfile> updateProfile(
      {required String displayName,
      String? dateOfBirth,
      String? avatarId}) async {
    final j = await _call('POST', '/me/profile', body: {
      'displayName': displayName,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      if (avatarId != null) 'avatarId': avatarId,
    }) as Map;
    return UserProfile.fromJson((j['user'] as Map).cast());
  }

  Future<Map<String, dynamic>> wallet() async =>
      ((await _call('GET', '/me/wallet')) as Map).cast();

  Future<List<Map<String, dynamic>>> games() async =>
      (((await _call('GET', '/games', auth: false)) as Map)['games'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  Future<TicketResponse> ticket(String gameId, String mode) async {
    final j = await _call('POST', '/matchmaking/ticket',
        body: {'gameId': gameId, 'mode': mode}) as Map;
    return TicketResponse(j['ticket'] as String, (j['options'] as Map).cast());
  }

  Future<String> roomIdForCode(String code) async => ((await _call(
          'GET', '/rooms/by-code/${Uri.encodeComponent(code.toUpperCase())}'))
      as Map)['roomId'] as String;

  Future<void> report(
          {required String userId,
          required String reason,
          String? roomId,
          String? note}) =>
      _call('POST', '/safety/reports', body: {
        'reportedUserId': userId,
        'reason': reason,
        if (roomId != null) 'roomId': roomId,
        if (note != null) 'note': note,
      });

  Future<void> block(String userId) =>
      _call('POST', '/safety/blocks', body: {'userId': userId});
}
