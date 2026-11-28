import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

/// Football Challenges: what sits inside the white question card.
/// Lines arrive from the server one by one (player clues, career clubs);
/// lines not revealed yet are drawn as locked slots.

const footballModeEmoji = {
  'player': '🕵️',
  'career': '🧭',
  'shared': '🤝',
  'transfer': '🔁',
  'history': '📜',
  'mixed': '🎲',
};

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// "2025-06-30" -> "يونيو 2025".
String asOfLabel(String iso) {
  final parts = iso.split('-');
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return iso;
  return '${_months[m - 1]} ${parts[0]}';
}

class FootballCardBody extends StatelessWidget {
  const FootballCardBody({super.key, required this.card, required this.prompt});
  final FootballCard card;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final ask = switch (card.mode) {
      'history' => null,
      'shared' => S.of(card.totalLines == 2 ? 'fbAsk_shared2' : 'fbAsk_shared'),
      _ => S.of('fbAsk_${card.mode}'),
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (card.when != null && card.mode != 'transfer') ...[
        _WhenChip(text: card.when!),
        const SizedBox(height: Tokens.s8),
      ],
      if (card.mode == 'history')
        Text(prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.ink,
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w800))
      else ...[
        Text(ask!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.ink, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s12),
        switch (card.mode) {
          'player' => _Clues(card: card),
          'career' => _Career(card: card),
          'shared' => _Shared(card: card),
          _ => _Transfer(card: card),
        },
      ],
      if (card.asOf != null) ...[
        const SizedBox(height: Tokens.s12),
        Text('📅 ${S.of('fbAsOf')} ${asOfLabel(card.asOf!)}',
            style: const TextStyle(
                color: Tokens.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

class _WhenChip extends StatelessWidget {
  const _WhenChip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: Tokens.orange.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(Radius.circular(99)),
        ),
        child: Text('🗓️ $text',
            style: const TextStyle(
                color: Color(0xFFB3561A),
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      );
}

/// A slot for a line the server has not revealed yet.
class _Locked extends StatelessWidget {
  const _Locked({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.s12, vertical: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: Tokens.ink.withValues(alpha: 0.05),
          borderRadius: const BorderRadius.all(Tokens.r12),
          border: Border.all(color: Tokens.ink.withValues(alpha: 0.08)),
        ),
        child: Text('🔒 ${S.of(compact ? 'fbLockedShort' : 'fbClueLocked')}',
            style: const TextStyle(
                color: Tokens.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

class _Clues extends StatelessWidget {
  const _Clues({required this.card});
  final FootballCard card;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < card.totalLines; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: i < card.lines.length
              ? FadeSlideIn(
                  key: ValueKey('clue$i'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Tokens.mint.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.all(Tokens.r12),
                    ),
                    child: Row(children: [
                      Text('${i + 1}',
                          style: const TextStyle(
                              color: Color(0xFF0E8C6C),
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(width: Tokens.s8),
                      Expanded(
                          child: Text(card.lines[i].text,
                              style: const TextStyle(
                                  color: Tokens.ink,
                                  fontSize: 15,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700))),
                    ]),
                  ),
                )
              : const SizedBox(width: double.infinity, child: _Locked()),
        ),
    ]);
  }
}

class _Career extends StatelessWidget {
  const _Career({required this.card});
  final FootballCard card;
  @override
  Widget build(BuildContext context) {
    Widget club(FootballLine l) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Tokens.sky.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.all(Tokens.r12),
            border: Border.all(color: Tokens.sky.withValues(alpha: 0.35)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l.text,
                style: const TextStyle(
                    color: Tokens.ink,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
            if (l.sub != null)
              Text(l.sub!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      color: Tokens.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
          ]),
        );
    final items = <Widget>[];
    for (var i = 0; i < card.totalLines; i++) {
      if (i > 0) {
        items.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('←',
              style: TextStyle(
                  color: Tokens.inkSoft,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ));
      }
      items.add(i < card.lines.length
          ? FadeSlideIn(key: ValueKey('club$i'), child: club(card.lines[i]))
          : const _Locked(compact: true));
    }
    return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 6,
        children: items);
  }
}

class _ClubBadge extends StatelessWidget {
  const _ClubBadge({required this.name, required this.color, this.label});
  final String name;
  final Color color;
  final String? label;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (label != null)
          Text(label!,
              style: const TextStyle(
                  color: Tokens.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Container(
          constraints: const BoxConstraints(minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Tokens.r16),
            boxShadow: [
              BoxShadow(
                  color: Tokens.shade(color, 0.25), offset: const Offset(0, 4))
            ],
          ),
          child: Text(name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Tokens.onColor(color),
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w900)),
        ),
      ]);
}

class _Shared extends StatelessWidget {
  const _Shared({required this.card});
  final FootballCard card;
  static const _colors = [Tokens.coral, Tokens.sky, Tokens.grape];
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final (i, l) in card.lines.indexed) {
      if (i > 0) {
        items.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('+',
              style: TextStyle(
                  color: Tokens.inkSoft,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
        ));
      }
      // Flexible must sit directly in the Row.
      items.add(Flexible(
          child: _ClubBadge(name: l.text, color: _colors[i % _colors.length])));
    }
    return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: items);
  }
}

class _Transfer extends StatelessWidget {
  const _Transfer({required this.card});
  final FootballCard card;
  @override
  Widget build(BuildContext context) {
    final from = card.lines.where((l) => l.sub == 'from').firstOrNull;
    final to = card.lines.where((l) => l.sub == 'to').firstOrNull;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (from != null)
          Flexible(
              child: _ClubBadge(
                  name: from.text, color: Tokens.grape, label: S.of('fbFrom'))),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 18, 8, 0),
          child: Text('⬅️', style: TextStyle(fontSize: 24)),
        ),
        if (to != null)
          Flexible(
              child: _ClubBadge(
                  name: to.text, color: Tokens.mint, label: S.of('fbTo'))),
      ]),
      const SizedBox(height: Tokens.s12),
      Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            if (card.when != null) _WhenChip(text: card.when!),
            if (card.detail != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.success.withValues(alpha: 0.14),
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                ),
                child: Text('💰 ${card.detail}',
                    style: const TextStyle(
                        color: Color(0xFF128A4E),
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
          ]),
    ]);
  }
}

/// Football Duel: the two players face to face with questions won.
class DuelBar extends StatelessWidget {
  const DuelBar(
      {super.key, required this.view, required this.wins, this.winner});
  final RoomView view;
  final Map<String, int> wins;

  /// Who won the question just revealed (gets a crown).
  final String? winner;

  @override
  Widget build(BuildContext context) {
    final ps = view.players.where((p) => wins.containsKey(p.playerId)).toList()
      ..sort((a, b) =>
          a.playerId == view.you ? -1 : (b.playerId == view.you ? 1 : 0));
    if (ps.length != 2) return const SizedBox.shrink();
    Widget side(PublicPlayer p) => Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              ChibiAvatar(
                  avatarId: p.avatarId, frame: p.cosmetics?.frame, size: 40),
              if (winner == p.playerId)
                const Positioned(
                    top: -14,
                    left: 0,
                    right: 0,
                    child: PopIn(
                        child: Text('👑',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18)))),
            ]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(p.playerId == view.you ? S.of('you') : p.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ]),
        );
    return GlassCard(
      key: const Key('duelBar'),
      radius: Tokens.r20,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: 6),
      child: Row(children: [
        side(ps[0]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: const BoxDecoration(
            color: Tokens.sun,
            borderRadius: BorderRadius.all(Radius.circular(99)),
          ),
          // Laid out in the same direction as the two sides around it.
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in [
              '${wins[ps[0].playerId] ?? 0}',
              ':',
              '${wins[ps[1].playerId] ?? 0}'
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(t,
                    style: const TextStyle(
                        color: Tokens.ink,
                        fontFamily: Tokens.display,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
              ),
          ]),
        ),
        side(ps[1]),
      ]),
    );
  }
}
