import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'room.dart';

const gameEmoji = {
  'quiz': '🧠',
  'spy': '🕵️',
  'liar': '🤥',
  'who': '👀',
  'emoji': '😎',
  'stop': '🚌',
  'memory': '🧩',
  'draw': '🎨',
  'football': '⚽',
  'acting': '🎭',
};

String friendErrorText(String code) => switch (code) {
      'player_not_found' => S.of('friendsNotFound'),
      'too_many_friends' => S.of('friendsTooMany'),
      'too_many_requests' => S.of('friendsTooManyRequests'),
      'cannot_add_self' ||
      'cannot_add' ||
      'account_not_eligible' =>
        S.of('friendsCannotAdd'),
      _ => S.of('error'),
    };

/// Friends: your code, add by code, requests, the list with online status,
/// invitations and privacy settings.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _code = TextEditingController();
  FriendsOverview? _data;
  String? _error;
  String? _note;
  bool _busy = false;
  Timer? _refresh;

  SahraApi get api => AppScope.read(context).api;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await api.friends();
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted && _data == null) setState(() => _error = S.of('error'));
    }
  }

  Future<void> _act(Future<void> Function() f) async {
    try {
      await f();
    } on ApiException catch (e) {
      _toast(friendErrorText(e.code));
    } catch (_) {
      _toast(S.of('error'));
    }
    await _load();
    if (mounted) AppScope.read(context).pingFriends();
  }

  Future<void> _add() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 8) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final status = await api.addFriend(code: code);
      _code.clear();
      setState(() => _note =
          S.of(status == 'friends' ? 'friendsNowFriends' : 'friendsRequested'));
      HapticFeedback.mediumImpact();
    } on ApiException catch (e) {
      setState(() => _note = friendErrorText(e.code));
    } catch (_) {
      setState(() => _note = S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _remove(FriendPlayer f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.displayName),
        content: Text(S.of('friendsRemoveConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of('friendsCancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.of('friendsRemove'),
                  style: const TextStyle(color: Tokens.coral))),
        ],
      ),
    );
    if (ok == true) await _act(() => api.removeFriend(f.id));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return NightScaffold(
      glow: Tokens.mint,
      title: Text(S.of('friends'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      body: d == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(color: Tokens.sun))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s20, Tokens.s8, Tokens.s20, Tokens.s32),
                children: [
                  if (d.code != null) FadeSlideIn(child: _myCode(d.code!)),
                  const SizedBox(height: Tokens.s12),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 60), child: _adder()),
                  if (d.invites.isNotEmpty) ...[
                    _section(S.of('friendsInvites'), d.invites.length),
                    for (final i in d.invites) InviteCard(invite: i),
                  ],
                  if (d.incoming.isNotEmpty) ...[
                    _section(S.of('friendsIncoming'), d.incoming.length),
                    for (final p in d.incoming)
                      _row(p, trailing: [
                        _smallButton(S.of('friendsAccept'), Tokens.success,
                            () => _act(() => api.acceptFriend(p.id)),
                            key: Key('accept_${p.id}')),
                        const SizedBox(width: 6),
                        _smallButton(S.of('friendsDecline'), Tokens.glass,
                            () => _act(() => api.declineFriend(p.id))),
                      ]),
                  ],
                  _section(S.of('friendsList'), d.friends.length),
                  if (d.friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Tokens.s12),
                      child: Column(children: [
                        const Bob(
                            child: Text('🫂', style: TextStyle(fontSize: 54))),
                        const SizedBox(height: Tokens.s8),
                        Text(S.of('friendsEmpty'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Tokens.textDim, height: 1.5)),
                      ]),
                    ),
                  for (final f in d.friends)
                    _row(f,
                        status: true,
                        onLongPress: () => _remove(f),
                        trailing: [
                          RoundIconButton(
                              icon: Icons.more_horiz_rounded,
                              tooltip: S.of('friendsRemove'),
                              onPressed: () => _remove(f)),
                        ]),
                  if (d.outgoing.isNotEmpty) ...[
                    _section(S.of('friendsOutgoing'), d.outgoing.length),
                    for (final p in d.outgoing)
                      _row(p, trailing: [
                        _smallButton(S.of('friendsCancel'), Tokens.glass,
                            () => _act(() => api.cancelFriendRequest(p.id))),
                      ]),
                  ],
                  _section(S.of('friendsSettings'), null),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s12, vertical: 4),
                    child: Column(children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(S.of('friendsAllowRequests'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        value: d.settings.allowFriendRequests,
                        activeThumbColor: Tokens.mint,
                        onChanged: (v) => _act(() =>
                            api.updateFriendsSettings(allowFriendRequests: v)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(S.of('friendsShowPresence'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        value: d.settings.showPresence,
                        activeThumbColor: Tokens.mint,
                        onChanged: (v) => _act(
                            () => api.updateFriendsSettings(showPresence: v)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: Tokens.s12),
                  Text('🛡️ ${S.of('friendsAgeNote')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Tokens.textFaint, fontSize: 13, height: 1.5)),
                ],
              ),
            ),
    );
  }

  Widget _myCode(String code) => GlassCard(
        padding: const EdgeInsets.all(Tokens.s16),
        child: Column(children: [
          Text(S.of('friendsMyCode'),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s8),
          Text(code,
              key: const Key('myFriendCode'),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  fontFamily: Tokens.body,
                  color: Tokens.sun,
                  fontSize: 30,
                  letterSpacing: 5,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(S.of('friendsMyCodeHint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
          const SizedBox(height: Tokens.s12),
          GameButton(
              label: S.of('friendsCopy'),
              icon: Icons.copy_rounded,
              color: Tokens.grape,
              size: GameButtonSize.medium,
              expand: false,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                _toast(S.of('friendsCodeCopied'));
              }),
        ]),
      );

  Widget _adder() => GlassCard(
        padding: const EdgeInsets.all(Tokens.s16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('➕ ${S.of('friendsAddTitle')}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.s12),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('friendCodeField'),
                controller: _code,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  TextInputFormatter.withFunction(
                      (o, n) => n.copyWith(text: n.text.toUpperCase())),
                ],
                onSubmitted: (_) => _add(),
                style: const TextStyle(
                    fontFamily: Tokens.body,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w900),
                decoration: InputDecoration(
                    hintText: S.of('friendsAddHint'),
                    hintStyle: const TextStyle(
                        letterSpacing: 0, color: Tokens.textFaint),
                    counterText: ''),
              ),
            ),
            const SizedBox(width: Tokens.s12),
            GameButton(
                key: const Key('friendAdd'),
                label: S.of('friendsAdd'),
                expand: false,
                busy: _busy,
                color: Tokens.mint,
                onPressed: _busy ? null : _add),
          ]),
          if (_note != null) ...[
            const SizedBox(height: Tokens.s8),
            Text(_note!,
                key: const Key('friendNote'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ]),
      );

  Widget _section(String title, int? n) => Padding(
        padding: const EdgeInsets.only(top: Tokens.s20, bottom: Tokens.s8),
        child: Row(children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (n != null && n > 0) ...[
            const SizedBox(width: Tokens.s8),
            Pill(text: '$n', color: Tokens.sky),
          ],
        ]),
      );

  Widget _smallButton(String label, Color color, VoidCallback onTap,
          {Key? key}) =>
      Pressable(
        key: key,
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(99)),
            border: Border.all(color: Tokens.glassBorder),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      );

  Widget _row(FriendPlayer p,
          {bool status = false,
          List<Widget> trailing = const [],
          VoidCallback? onLongPress}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: GlassCard(
            radius: Tokens.r16,
            padding:
                const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: 8),
            child: Row(children: [
              FriendAvatar(player: p, showStatus: status),
              const SizedBox(width: Tokens.s12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      if (status)
                        Text(statusText(p),
                            style: TextStyle(
                                color: statusColor(p.status), fontSize: 13)),
                    ]),
              ),
              ...trailing,
            ]),
          ),
        ),
      );
}

Color statusColor(String s) => switch (s) {
      'online' => Tokens.success,
      'in_game' => Tokens.sun,
      _ => Tokens.textFaint,
    };

String statusText(FriendPlayer p) => switch (p.status) {
      'online' => S.of('friendsOnline'),
      'in_game' =>
        '${S.of('friendsInGame')} ${gameEmoji[p.gameId] ?? ''} ${p.gameId == null ? '' : S.of('game_${p.gameId}')}',
      _ => S.of('friendsOffline'),
    };

class FriendAvatar extends StatelessWidget {
  const FriendAvatar(
      {super.key,
      required this.player,
      this.showStatus = true,
      this.size = 44});
  final FriendPlayer player;
  final bool showStatus;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Stack(clipBehavior: Clip.none, children: [
        ChibiAvatar(
            avatarId: player.avatarId,
            size: size,
            expression: player.status == 'offline' && showStatus
                ? ChibiExpression.neutral
                : ChibiExpression.happy),
        if (showStatus)
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: statusColor(player.status),
                shape: BoxShape.circle,
                border: Border.all(color: Tokens.nightDeep, width: 2.5),
              ),
            ),
          ),
      ]);
}

/// A friend's invitation to a private room: join or dismiss.
class InviteCard extends StatefulWidget {
  const InviteCard({super.key, required this.invite});
  final FriendInvite invite;
  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  bool _busy = false;

  Future<void> _join() async {
    final app = AppScope.read(context);
    final i = widget.invite;
    setState(() => _busy = true);
    try {
      final session = await GameSession.joinByCode(app.api, app.client,
          gameId: i.gameId, code: i.roomCode);
      await app.dismissInvite(i);
      if (!mounted) return;
      await Navigator.of(context).push(SoftRoute(RoomScreen(session: session)));
    } on ApiException catch (e) {
      if (e.code == 'room_not_found') await app.dismissInvite(i);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(S.of(e.code == 'room_not_found'
                ? 'inviteGone'
                : e.code == 'safe_mode_unavailable'
                    ? 'safeModeUnavailable'
                    : 'error'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.of('error'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invite;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s8),
      child: PopIn(
        child: Container(
          padding: const EdgeInsets.all(Tokens.s12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF7A4DFF), Color(0xFF3DA5FF)]),
            borderRadius: const BorderRadius.all(Tokens.r20),
            boxShadow: [
              BoxShadow(
                  color: Tokens.shade(Tokens.grape, 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 6))
            ],
          ),
          child: Row(children: [
            ChibiAvatar(avatarId: i.from.avatarId, size: 46),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.from.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(
                        '${S.of('inviteFrom')} ${gameEmoji[i.gameId] ?? '🎮'} ${i.gameId.isEmpty ? '' : S.of('game_${i.gameId}')}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
            ),
            GameButton(
                key: Key('inviteJoin_${i.id}'),
                label: S.of('inviteJoin'),
                expand: false,
                busy: _busy,
                size: GameButtonSize.medium,
                color: Tokens.sun,
                onPressed: _busy ? null : _join),
            const SizedBox(width: 4),
            RoundIconButton(
                icon: Icons.close_rounded,
                tooltip: S.of('inviteNo'),
                onPressed: () => AppScope.read(context).dismissInvite(i)),
          ]),
        ),
      ),
    );
  }
}

/// Room lobby: pick friends to invite to this private room.
Future<void> showInviteFriendsSheet(
    BuildContext context, String roomCode, String gameId) {
  final api = AppScope.read(context).api;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) =>
        _InviteSheet(api: api, roomCode: roomCode, gameId: gameId),
  );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet(
      {required this.api, required this.roomCode, required this.gameId});
  final SahraApi api;
  final String roomCode;
  final String gameId;
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  List<FriendPlayer>? _friends;
  final _sent = <String>{};

  @override
  void initState() {
    super.initState();
    widget.api.friends().then((d) {
      if (mounted) setState(() => _friends = d.friends);
    }).catchError((_) {
      if (mounted) setState(() => _friends = const []);
    });
  }

  Future<void> _invite(FriendPlayer f) async {
    setState(() => _sent.add(f.id));
    HapticFeedback.selectionClick();
    try {
      await widget.api.inviteFriend(f.id, widget.roomCode, widget.gameId);
    } catch (_) {
      if (mounted) setState(() => _sent.remove(f.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = _friends;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('📨 ${S.of('inviteFriends')}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Tokens.s12),
            if (fs == null)
              const Padding(
                  padding: EdgeInsets.all(Tokens.s24),
                  child: CircularProgressIndicator(color: Tokens.sun))
            else if (fs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Tokens.s16),
                child: Text(S.of('inviteNone'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Tokens.textDim)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final f in fs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.s8),
                      child: Row(children: [
                        FriendAvatar(player: f, size: 40),
                        const SizedBox(width: Tokens.s12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(statusText(f),
                                    style: TextStyle(
                                        color: statusColor(f.status),
                                        fontSize: 12)),
                              ]),
                        ),
                        GameButton(
                            key: Key('invite_${f.id}'),
                            label: _sent.contains(f.id)
                                ? S.of('inviteSent')
                                : S.of('inviteSend'),
                            expand: false,
                            size: GameButtonSize.medium,
                            color: _sent.contains(f.id)
                                ? Tokens.success
                                : Tokens.sun,
                            onPressed:
                                _sent.contains(f.id) ? null : () => _invite(f)),
                      ]),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
