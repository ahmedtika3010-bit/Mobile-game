import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

/// S.of with {placeholders} filled in.
String sf(String key, Map<String, Object> args) {
  var t = S.of(key);
  args.forEach((k, v) => t = t.replaceAll('{$k}', '$v'));
  return t;
}

String progressErrorText(String code) =>
    S.has(code) ? S.of(code) : S.of('error');

/// "5 س 20 د" until a time (server ms).
String timeLeft(int endsAt, int now) {
  final m = ((endsAt - now) / 60000).ceil().clamp(0, 1 << 30);
  if (m >= 48 * 60) return '${(m / 1440).floor()} ${S.of('daysShort')}';
  if (m >= 60) {
    return '${m ~/ 60} ${S.of('hoursShort')} ${m % 60} ${S.of('minutesShort')}';
  }
  return '$m ${S.of('minutesShort')}';
}

/// The reward as small pills: coins, gems, XP and an item.
class RewardPills extends StatelessWidget {
  const RewardPills(
      {super.key, required this.reward, this.itemName, this.dim = false});
  final Reward reward;
  final String? itemName;
  final bool dim;
  @override
  Widget build(BuildContext context) {
    final r = reward;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        if (r.coins > 0)
          Pill(emoji: '🪙', text: '${r.coins}', color: Tokens.orange),
        if (r.gems > 0) Pill(emoji: '💎', text: '${r.gems}', color: Tokens.sky),
        if (r.xp > 0)
          Pill(emoji: '⭐', text: '${r.xp} ${S.of('xp')}', color: Tokens.sun),
        if (r.item != null)
          Pill(
              emoji: '🎁',
              text: itemName ?? S.of('rewardItem'),
              color: Tokens.pink),
      ]),
    );
  }
}

/// A rounded progress bar with "3/5" next to it.
class ProgressLine extends StatelessWidget {
  const ProgressLine(
      {super.key,
      required this.progress,
      required this.target,
      this.color = Tokens.mint});
  final int progress;
  final int target;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final v = target == 0 ? 1.0 : (progress / target).clamp(0.0, 1.0);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(99)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: Tokens.medium,
            builder: (_, x, __) => LinearProgressIndicator(
                value: x,
                minHeight: 9,
                color: color,
                backgroundColor: Tokens.glass),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('$progress/$target',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Tokens.textDim)),
    ]);
  }
}

/// A small celebration after claiming a reward.
Future<void> showRewardDialog(BuildContext context, Reward r,
    {String? itemName, String? note}) {
  Sfx.play('win', volume: 0.6);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Tokens.plum,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Tokens.r24)),
      child: Stack(children: [
        const Positioned.fill(child: IgnorePointer(child: Confetti())),
        Padding(
          padding: const EdgeInsets.all(Tokens.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PopIn(child: Text('🎁', style: TextStyle(fontSize: 64))),
            const SizedBox(height: Tokens.s8),
            Text(S.of('rewardTitle'),
                style: Theme.of(ctx).textTheme.headlineSmall),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tokens.textDim)),
            ],
            const SizedBox(height: Tokens.s16),
            RewardPills(reward: r, itemName: itemName),
            const SizedBox(height: Tokens.s20),
            GameButton(
                label: S.of('ok'),
                color: Tokens.sun,
                size: GameButtonSize.medium,
                onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
      ]),
    ),
  );
}

void progressToast(BuildContext context, String t) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));
}

/// A section header: title and an optional trailing note.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {super.key, required this.title, this.trailing, this.emoji});
  final String title;
  final String? trailing;
  final String? emoji;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Tokens.s20, bottom: Tokens.s8),
        child: Row(children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
          ],
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: Tokens.textDim, fontWeight: FontWeight.w700)),
        ]),
      );
}
