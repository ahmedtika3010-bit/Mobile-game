import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sahra_client/sahra_client.dart';

import 'config.dart';

class SecureTokenStore implements TokenStore {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
}

class AppState extends ChangeNotifier {
  AppState({SahraApi? api, ColyseusClient? client})
      : api = api ?? SahraApi(AppConfig.serverUrl, store: SecureTokenStore()),
        client = client ?? ColyseusClient(AppConfig.serverUrl);

  final SahraApi api;
  final ColyseusClient client;
  UserProfile? user;
  bool loading = true;

  /// Coins, gems, xp and level from the server; null until loaded.
  Map<String, dynamic>? wallet;

  /// Friends: pending requests and live room invitations (from the ping).
  int friendRequests = 0;
  List<FriendInvite> invites = const [];
  Timer? _friendsTimer;

  bool get signedIn => user != null;
  bool get canPlay => user?.onboarded == true && user?.status == 'active';

  Future<void> init() async {
    try {
      if (await api.isSignedIn) user = await api.me();
      if (canPlay) await refreshWallet(notify: false);
    } catch (_) {
      user = null;
    } finally {
      loading = false;
      _syncFriends();
      notifyListeners();
    }
  }

  /// Starts or stops the friends ping (online status + invitations).
  void _syncFriends() {
    if (canPlay) {
      _friendsTimer ??=
          Timer.periodic(const Duration(seconds: 45), (_) => pingFriends());
      pingFriends();
    } else {
      _friendsTimer?.cancel();
      _friendsTimer = null;
      friendRequests = 0;
      invites = const [];
    }
  }

  Future<void> pingFriends() async {
    if (!canPlay) return;
    try {
      final p = await api.pingFriends();
      final changed = p.incoming != friendRequests ||
          p.invites.map((i) => i.id).join() != invites.map((i) => i.id).join();
      friendRequests = p.incoming;
      invites = p.invites;
      if (changed) notifyListeners();
    } catch (_) {
      // Offline for a moment: keep the last values.
    }
  }

  Future<void> dismissInvite(FriendInvite i) async {
    invites = invites.where((x) => x.id != i.id).toList();
    notifyListeners();
    try {
      await api.dismissInvite(i.id);
    } catch (_) {}
  }

  Future<void> afterSignIn(UserProfile p) async {
    user = p;
    if (canPlay) await refreshWallet(notify: false);
    _syncFriends();
    notifyListeners();
  }

  Future<void> refreshWallet({bool notify = true}) async {
    try {
      wallet = await api.wallet();
    } catch (_) {
      // Wallet is decorative on these screens; keep the last value.
    }
    if (notify) notifyListeners();
  }

  Future<void> onboard(
      {required String displayName,
      required String dob,
      required String avatarId}) async {
    user = await api.updateProfile(
        displayName: displayName,
        dateOfBirth: user?.ageBand == 'unknown' ? dob : null,
        avatarId: avatarId);
    if (canPlay) await refreshWallet(notify: false);
    _syncFriends();
    notifyListeners();
  }

  Future<void> signOut() async {
    await api.signOut();
    user = null;
    wallet = null;
    _syncFriends();
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
