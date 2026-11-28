import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'friends.dart' show gameEmoji;
import 'progress_common.dart';

/// Account-wide and per-game achievements, with their rewards.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  List<Achievement>? _list;
  Map<String, String> _itemNames = const {};
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
      final list = await api.achievements();
      final shop = await api.shop();
      if (mounted) {
        setState(() {
          _list = list;
          _itemNames = {for (final i in shop.items) i.id: i.name};
        });
      }
    } catch (_) {
      if (mounted && _list == null) setState(() => _error = S.of('error'));
    }
  }

  Future<void> _claim(Achievement a) async {
    setState(() => _busy = a.id);
    try {
      final r = await api.claimAchievement(a.id);
      if (mounted) {
        await showRewardDialog(context, r, itemName: _itemNames[r.item]);
      }
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

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return NightScaffold(
      glow: Tokens.grape,
      title: Text(S.of('hubAchievements'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      body: list == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(color: Tokens.sun))
          : _body(list),
    );
  }

  Widget _body(List<Achievement> list) {
    final general = list.where((a) => a.gameId == null).toList();
    final games = <String>[];
    for (final a in list) {
      if (a.gameId != null && !games.contains(a.gameId)) games.add(a.gameId!);
    }
    // Ready to claim first, then the closest to done.
    int order(Achievement a) => a.ready ? 0 : (a.claimed ? 2 : 1);
    general.sort((a, b) {
      final o = order(a).compareTo(order(b));
      return o != 0
          ? o
          : (b.progress / b.target).compareTo(a.progress / a.target);
    });
    final done = list.where((a) => a.claimed).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s20, Tokens.s8, Tokens.s20, Tokens.s32),
        children: [
          FadeSlideIn(
            child: GlassCard(
              child: Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 40)),
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: ProgressLine(
                      progress: done, target: list.length, color: Tokens.sun),
                ),
              ]),
            ),
          ),
          SectionHeader(emoji: '⭐', title: S.of('achGeneral')),
          for (final a in general) _card(a),
          for (final g in games) ...[
            SectionHeader(emoji: gameEmoji[g], title: S.of('game_$g')),
            for (final a in list.where((x) => x.gameId == g)) _card(a),
          ],
        ],
      ),
    );
  }

  String _title(Achievement a) {
    if (a.gameId == null) return S.of('ach_${a.id}');
    return sf(
        a.kind == 'wins' ? 'achGameWins' : 'achGameMatches', {'n': a.target});
  }

  String _desc(Achievement a) => sf('achd_${a.kind}', {'n': a.target});

  String _emoji(Achievement a) => a.gameId != null
      ? (a.kind == 'wins' ? '🥇' : '🎯')
      : switch (a.kind) {
          'matches' => '🎮',
          'wins' => '🏆',
          'distinct' => '🧭',
          'level' => '⭐',
          'friends' => '🤝',
          'nights' => '🌙',
          _ => '🏅',
        };

  Widget _card(Achievement a) {
    final color = a.claimed
        ? Tokens.sun
        : a.ready
            ? Tokens.success
            : Tokens.grape;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s8),
      child: GlassCard(
        key: Key('ach_${a.id}'),
        padding: const EdgeInsets.all(Tokens.s12),
        color: a.claimed ? Tokens.sun.withValues(alpha: 0.08) : Tokens.glass,
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
              border: Border.all(color: color, width: 2),
            ),
            child: Opacity(
                opacity: a.claimed || a.ready ? 1 : 0.55,
                child: Text(_emoji(a), style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: Tokens.s12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(a),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15.5)),
              Text(_desc(a),
                  style:
                      const TextStyle(color: Tokens.textDim, fontSize: 12.5)),
              if (!a.claimed) ...[
                const SizedBox(height: 6),
                ProgressLine(
                    progress: a.progress, target: a.target, color: color),
              ],
              const SizedBox(height: 6),
              RewardPills(
                  reward: a.reward,
                  itemName: _itemNames[a.reward.item],
                  dim: a.claimed),
            ]),
          ),
          const SizedBox(width: Tokens.s8),
          if (a.claimed)
            const Icon(Icons.verified_rounded, color: Tokens.sun, size: 30)
          else if (a.ready)
            GameButton(
                label: S.of('claim'),
                expand: false,
                size: GameButtonSize.medium,
                color: Tokens.success,
                busy: _busy == a.id,
                onPressed: _busy == null ? () => _claim(a) : null),
        ]),
      ),
    );
  }
}
