import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'friends.dart' show gameEmoji;
import 'progress_common.dart';

/// Daily login track, daily missions and weekly missions.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});
  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  MissionsView? _m;
  String? _error;
  String? _busy;

  SahraApi get api => AppScope.read(context).api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await api.missions();
      if (mounted) setState(() => _m = m);
    } catch (_) {
      if (mounted && _m == null) setState(() => _error = S.of('error'));
    }
  }

  Future<void> _claim(String what, Future<void> Function() f) async {
    setState(() => _busy = what);
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) progressToast(context, progressErrorText(e.code));
    } catch (_) {
      if (mounted) progressToast(context, S.of('error'));
    }
    if (!mounted) return;
    setState(() => _busy = null);
    await _load();
    if (mounted) {
      final app = AppScope.read(context);
      app.refreshWallet();
      app.refreshProgress();
    }
  }

  Future<void> _claimLogin() => _claim('login', () async {
        final (r, wb) = await api.claimLogin();
        if (!mounted) return;
        await showRewardDialog(context, r);
        if (wb != null && mounted) {
          await showRewardDialog(context, wb, note: S.of('welcomeBack'));
        }
      });

  Future<void> _claimMission(Mission m) => _claim(m.id, () async {
        final r = await api.claimMission(m.id);
        if (mounted) await showRewardDialog(context, r);
      });

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final now = DateTime.now().millisecondsSinceEpoch;
    return NightScaffold(
      glow: Tokens.sun,
      title: Text(S.of('hubMissions'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      body: m == null
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
                  FadeSlideIn(child: _loginCard(m.login)),
                  SectionHeader(
                      emoji: '☀️',
                      title: S.of('missionsDaily'),
                      trailing:
                          '${S.of('missionsRenew')} ${timeLeft(m.dailyEndsAt, now)}'),
                  for (final (i, x) in m.daily.indexed)
                    FadeSlideIn(
                        delay: Duration(milliseconds: 40 * i),
                        child: _missionCard(x)),
                  SectionHeader(
                      emoji: '📅',
                      title: S.of('missionsWeekly'),
                      trailing:
                          '${S.of('missionsRenew')} ${timeLeft(m.weeklyEndsAt, now)}'),
                  for (final (i, x) in m.weekly.indexed)
                    FadeSlideIn(
                        delay: Duration(milliseconds: 40 * i),
                        child: _missionCard(x)),
                  const SizedBox(height: Tokens.s12),
                  Text(S.of('missionsHint'),
                      style: const TextStyle(
                          color: Tokens.textFaint, fontSize: 13, height: 1.5)),
                ],
              ),
            ),
    );
  }

  Widget _loginCard(LoginTrack l) {
    final today = l.step;
    return GlassCard(
      key: const Key('loginCard'),
      color: Tokens.plum.withValues(alpha: 0.75),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.of('loginTitle'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(S.of('loginHint'),
            style: const TextStyle(color: Tokens.textDim, fontSize: 13)),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          for (var i = 1; i <= l.rewards.length; i++)
            Expanded(
                child: _loginDay(i, l.rewards[i - 1],
                    done: i < today || (i == today && l.claimedToday),
                    current: i == today)),
        ]),
        const SizedBox(height: Tokens.s12),
        if (l.claimedToday)
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Tokens.success),
            const SizedBox(width: 6),
            Expanded(
                child: Text(S.of('loginDone'),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ])
        else
          GameButton(
              key: const Key('loginClaim'),
              label: S.of('loginClaim'),
              icon: Icons.card_giftcard_rounded,
              color: Tokens.sun,
              size: GameButtonSize.medium,
              busy: _busy == 'login',
              onPressed: _busy == null ? _claimLogin : null),
      ]),
    );
  }

  Widget _loginDay(int day, Reward r,
      {required bool done, required bool current}) {
    final big = r.gems > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedContainer(
        duration: Tokens.fast,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: current
              ? Tokens.sun.withValues(alpha: done ? 0.18 : 0.3)
              : Tokens.glass,
          borderRadius: const BorderRadius.all(Tokens.r12),
          border: Border.all(
              color: current ? Tokens.sun : Tokens.glassBorder,
              width: current ? 2 : 1),
        ),
        child: Column(children: [
          Text('${S.of('loginDay')} $day',
              style: const TextStyle(fontSize: 10.5, color: Tokens.textDim)),
          const SizedBox(height: 2),
          Text(done ? '✅' : (big ? '💎' : '🪙'),
              style: const TextStyle(fontSize: 20)),
          FittedBox(
            child: Text(big ? '${r.gems}' : '${r.coins}',
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  String _missionText(Mission m) {
    final k = 'm_${m.kind}';
    if (m.target == 1 && S.has('${k}_1')) return S.of('${k}_1');
    return sf(k, {
      'n': m.target,
      'game': m.gameId == null ? '' : S.of('game_${m.gameId}'),
    });
  }

  String _missionEmoji(Mission m) => switch (m.kind) {
        'play_any' => '🎮',
        'play_distinct' => '🎲',
        'win' => '🏆',
        'play_game' => gameEmoji[m.gameId] ?? '🎮',
        'perf' => '📈',
        'private' => '🔑',
        'night' => '🌙',
        _ => '⭐',
      };

  Widget _missionCard(Mission m) {
    final color = m.claimed
        ? Tokens.textFaint
        : m.ready
            ? Tokens.success
            : Tokens.mint;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s8),
      child: GlassCard(
        key: Key('mission_${m.id}'),
        padding: const EdgeInsets.all(Tokens.s12),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.all(Tokens.r16)),
            child: Text(_missionEmoji(m), style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: Tokens.s12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_missionText(m),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      decoration:
                          m.claimed ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 6),
              ProgressLine(
                  progress: m.progress, target: m.target, color: color),
              const SizedBox(height: 6),
              RewardPills(reward: m.reward, dim: m.claimed),
            ]),
          ),
          const SizedBox(width: Tokens.s8),
          if (m.claimed)
            const Icon(Icons.check_circle_rounded,
                color: Tokens.success, size: 30)
          else if (m.ready)
            GameButton(
                label: S.of('claim'),
                expand: false,
                size: GameButtonSize.medium,
                color: Tokens.success,
                busy: _busy == m.id,
                onPressed: _busy == null ? () => _claimMission(m) : null),
        ]),
      ),
    );
  }
}
