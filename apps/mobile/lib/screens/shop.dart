import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/cosmetics.dart';
import '../design/sfx.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import 'progress_common.dart';

const _tabs = ['frame', 'title', 'theme', 'effect', 'gems'];
const _tabLabels = {
  'frame': 'shopFrames',
  'title': 'shopTitles',
  'theme': 'shopThemes',
  'effect': 'shopEffects',
  'gems': 'shopGems',
};
const _rarityColor = {
  'common': Tokens.textDim,
  'rare': Tokens.sky,
  'epic': Tokens.grape,
  'legendary': Tokens.sun,
};

/// The cosmetic shop: everything is looks only, and every paid item can also
/// be earned by playing (level or achievement).
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ShopView? _shop;
  String? _error;
  String? _busy;
  String _tab = 'frame';

  /// An effect being previewed over the screen.
  CosmeticLook? _trying;
  int _tryKey = 0;

  SahraApi get api => AppScope.read(context).api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await api.shop();
      if (mounted) setState(() => _shop = s);
    } catch (_) {
      if (mounted && _shop == null) setState(() => _error = S.of('error'));
    }
  }

  Future<void> _run(String id, Future<ShopView> Function() f,
      {String? done}) async {
    setState(() => _busy = id);
    try {
      final s = await f();
      if (!mounted) return;
      setState(() => _shop = s);
      if (done != null) {
        Sfx.play('win', volume: 0.5);
        progressToast(context, done);
      }
      final app = AppScope.read(context);
      app.refreshWallet();
      app.refreshMe();
    } on ApiException catch (e) {
      if (mounted) progressToast(context, progressErrorText(e.code));
    } catch (_) {
      if (mounted) progressToast(context, S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _buy(ShopItem i) async {
    final price = '${i.priceAmount} ${i.priceCurrency == 'gems' ? '💎' : '🪙'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sf('shopBuyTitle', {'x': i.name})),
        content: Text(sf('shopBuyBody', {'p': price})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of('shopCancel'))),
          FilledButton(
              key: const Key('confirmBuy'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('${S.of('shopBuy')} $price')),
        ],
      ),
    );
    if (ok == true) {
      await _run(i.id, () => api.buyItem(i.id), done: S.of('shopBought'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shop;
    return NightScaffold(
      glow: Tokens.pink,
      title: Text(S.of('hubShop'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      actions: [
        if (s != null) ...[
          Pill(emoji: '🪙', text: '${s.coins}', color: Tokens.orange),
          const SizedBox(width: 6),
          Pill(emoji: '💎', text: '${s.gems}', color: Tokens.sky),
        ],
      ],
      body: s == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(color: Tokens.sun))
          : Stack(children: [
              Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s20, Tokens.s4, Tokens.s20, 0),
                  child: _preview(s),
                ),
                const SizedBox(height: Tokens.s12),
                _tabBar(),
                Expanded(child: _tab == 'gems' ? _gems() : _grid(s)),
              ]),
              if (_trying != null)
                Positioned.fill(
                    child: IgnorePointer(
                        child:
                            Confetti(key: ValueKey(_tryKey), look: _trying))),
            ]),
    );
  }

  Widget _preview(ShopView s) {
    final user = AppScope.of(context).user;
    final theme = s.equipped('theme')?.look;
    final content = Padding(
      padding: const EdgeInsets.all(Tokens.s16),
      child: Row(children: [
        ChibiAvatar(
            avatarId: user?.avatarId ?? '',
            size: 76,
            frame: s.equipped('frame')?.look),
        const SizedBox(width: Tokens.s16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.of('shopPreview'),
                style: const TextStyle(color: Tokens.textDim, fontSize: 12)),
            Text(user?.displayName ?? '',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            TitleTag(look: s.equipped('title')?.look, fontSize: 14),
            const SizedBox(height: 4),
            Pill(
                emoji: '⭐',
                text: '${S.of('level')} ${s.level}',
                color: Tokens.sun),
          ]),
        ),
      ]),
    );
    return theme == null
        ? GlassCard(padding: EdgeInsets.zero, child: content)
        : ThemeBackdrop(look: theme, child: content);
  }

  Widget _tabBar() => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
          children: [
            for (final t in _tabs)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  key: Key('shopTab_$t'),
                  label: Text(S.of(_tabLabels[t]!)),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
              ),
          ],
        ),
      );

  Widget _grid(ShopView s) {
    final items = s.items.where((i) => i.kind == _tab).toList()
      ..sort((a, b) {
        int rank(ShopItem i) => i.equipped ? 0 : (i.owned ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return a.priceAmount.compareTo(b.priceAmount);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Tokens.s20, Tokens.s12, Tokens.s20, Tokens.s32),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.74,
          children: [
            for (final (n, i) in items.indexed)
              FadeSlideIn(
                  delay: Duration(milliseconds: 30 * n), child: _card(s, i)),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        Text(S.of('shopFairNote'),
            style: const TextStyle(
                color: Tokens.textFaint, fontSize: 12.5, height: 1.5)),
      ],
    );
  }

  Widget _itemPreview(ShopItem i) {
    final user = AppScope.of(context).user;
    switch (i.kind) {
      case 'frame':
        return ChibiAvatar(
            avatarId: user?.avatarId ?? '', size: 74, frame: i.look);
      case 'title':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: Tokens.night.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.all(Tokens.r12)),
          child: TitleTag(look: i.look, fontSize: 15),
        );
      case 'theme':
        return SizedBox(
            width: 110,
            height: 74,
            child: ThemeBackdrop(look: i.look, radius: 14));
      default:
        final e = i.look.emojis.isEmpty ? ['🎊', '🎉'] : i.look.emojis;
        return Text(e.take(3).join(' '), style: const TextStyle(fontSize: 30));
    }
  }

  Widget _card(ShopView s, ShopItem i) {
    final rc = _rarityColor[i.rarity] ?? Tokens.textDim;
    final busy = _busy == i.id;
    final Widget action;
    if (i.equipped) {
      action = Pill(
          text: S.of('shopEquipped'),
          icon: Icons.check_rounded,
          color: Tokens.success,
          solid: true);
    } else if (i.owned) {
      action = GameButton(
          key: Key('equip_${i.id}'),
          label: S.of('shopEquip'),
          size: GameButtonSize.medium,
          color: Tokens.mint,
          busy: busy,
          onPressed: _busy == null
              ? () => _run(i.id, () => api.equipItem(i.kind, i.id))
              : null);
    } else if (i.forSale) {
      final gems = i.priceCurrency == 'gems';
      final enough = (gems ? s.gems : s.coins) >= i.priceAmount;
      action = GameButton(
          key: Key('buy_${i.id}'),
          label: '${gems ? '💎' : '🪙'} ${i.priceAmount}',
          size: GameButtonSize.medium,
          color: enough ? Tokens.sun : Tokens.textFaint,
          busy: busy,
          onPressed: _busy == null ? () => _buy(i) : null);
    } else {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_rounded, size: 16, color: Tokens.textDim),
        const SizedBox(width: 4),
        Flexible(
          child: Text(S.of('shopNotForSale'),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Tokens.textDim)),
        ),
      ]);
    }
    String? path;
    if (!i.owned) {
      if (i.unlockKind == 'level') {
        path = sf('shopFreeAtLevel', {'n': i.unlockLevel});
      } else if (i.unlockKind == 'achievement') {
        path = sf('shopFromAchievement',
            {'a': _achievementName(i.unlockAchievement ?? '')});
      }
    }
    return Container(
      key: Key('item_${i.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            i.equipped ? Tokens.success.withValues(alpha: 0.12) : Tokens.glass,
        borderRadius: const BorderRadius.all(Tokens.r20),
        border: Border.all(
            color: i.equipped ? Tokens.success : rc.withValues(alpha: 0.5),
            width: i.equipped ? 2 : 1),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: rc.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.all(Radius.circular(99))),
            child: Text(S.of('rarity_${i.rarity}'),
                style: TextStyle(
                    color: rc, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          if (i.event != null)
            Text('🏮 ${S.of('shopEvent')}',
                style: const TextStyle(fontSize: 10.5, color: Tokens.textDim)),
          if (i.kind == 'effect')
            InkWell(
              onTap: () => setState(() {
                _trying = i.look.emojis.isEmpty
                    ? const CosmeticLook(style: 'confetti')
                    : i.look;
                _tryKey++;
              }),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text('▶️ ${S.of('shopTry')}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        Expanded(child: Center(child: _itemPreview(i))),
        // A title's preview already is its name.
        if (i.kind != 'title')
          Text(i.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        SizedBox(
          height: 30,
          child: Center(
            child: path == null
                ? const SizedBox.shrink()
                : Text(path,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: Tokens.textDim, height: 1.25)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(height: 44, child: Center(child: action)),
      ]),
    );
  }

  String _achievementName(String id) {
    if (S.has('ach_$id')) return S.of('ach_$id');
    final parts = id.split('_');
    if (parts.length >= 3) {
      final n = parts.last;
      return '${S.of('game_${parts.first}')} · ${sf(parts[1] == 'wins' ? 'achGameWins' : 'achGameMatches', {
            'n': n
          })}';
    }
    return id;
  }

  Widget _gems() => ListView(
        padding: const EdgeInsets.all(Tokens.s20),
        children: [
          GlassCard(
            child: Column(children: [
              const Text('💎', style: TextStyle(fontSize: 56)),
              const SizedBox(height: Tokens.s8),
              Text(S.of('shopGemsSoon'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.6)),
            ]),
          ),
        ],
      );
}
