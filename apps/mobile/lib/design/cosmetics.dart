/// Drawing equipped cosmetics from their data description (CosmeticLook):
/// avatar frames, titles, theme backdrops and victory effects.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart' show CosmeticLook;

import 'tokens.dart';

Color hexColor(String hex, [Color fallback = Colors.white]) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

List<Color> lookColors(CosmeticLook? look, [Color fallback = Colors.white]) {
  final c = (look?.colors ?? const []).map((h) => hexColor(h)).toList();
  return c.isEmpty ? [fallback] : c;
}

/// A ring around an avatar. Keeps the outer size; the avatar shrinks inside.
/// Styles: solid, gradient, glow (gradient + soft light), double (two rings).
class FrameRing extends StatelessWidget {
  const FrameRing(
      {super.key,
      required this.look,
      required this.size,
      required this.builder});
  final CosmeticLook look;
  final double size;
  final Widget Function(double inner) builder;

  @override
  Widget build(BuildContext context) {
    final colors = lookColors(look);
    final ring = math.max(2.0, size * 0.065);
    final style = look.style ?? 'solid';
    final double gap = style == 'double' ? ring * 0.8 : 0.0;
    final inner =
        size - 2 * (ring + gap) - (style == 'double' ? ring * 1.2 : 0);
    final Gradient g = colors.length == 1
        ? LinearGradient(colors: [colors.first, colors.first])
        : SweepGradient(colors: [...colors, colors.first]);
    Widget child = builder(inner);
    if (style == 'double') {
      child = Container(
        padding: EdgeInsets.all(ring * 0.6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.last, width: ring * 0.6),
        ),
        child: child,
      );
    }
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: g,
        boxShadow: style == 'glow'
            ? [
                BoxShadow(
                    color: colors.first.withValues(alpha: 0.7),
                    blurRadius: size * 0.22),
              ]
            : null,
      ),
      child: Container(
        decoration:
            const BoxDecoration(shape: BoxShape.circle, color: Tokens.night),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// The equipped title as a small colored line under a name.
class TitleTag extends StatelessWidget {
  const TitleTag({super.key, required this.look, this.fontSize = 12});
  final CosmeticLook? look;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final text = look?.text;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: lookColors(look).first,
            fontSize: fontSize,
            fontWeight: FontWeight.w800));
  }
}

/// A theme as a backdrop: its gradient with its emoji faintly scattered.
class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop(
      {super.key, required this.look, this.child, this.radius = 24});
  final CosmeticLook look;
  final Widget? child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final c = lookColors(look, Tokens.plum);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: c.length == 1 ? [c.first, Tokens.night] : c),
      ),
      child: Stack(children: [
        for (final (i, e) in look.emojis.indexed)
          Positioned(
            top: 6.0 + 26 * i,
            left: 10.0 + 40 * i,
            child: Opacity(
                opacity: 0.35,
                child: Text(e, style: const TextStyle(fontSize: 26))),
          ),
        if (child != null) child!,
      ]),
    );
  }
}

/// Emoji particles: falling like rain, or bursting out from the middle.
class EmojiShower extends StatelessWidget {
  const EmojiShower(
      {super.key,
      required this.animation,
      required this.emojis,
      this.burst = false});
  final Animation<double> animation;
  final List<String> emojis;
  final bool burst;

  static final _bits = () {
    final r = math.Random(11);
    return List.generate(
        34,
        (i) => (
              r.nextDouble(),
              r.nextDouble() * 0.4,
              0.6 + r.nextDouble() * 0.6,
              r.nextDouble() * math.pi * 2,
              18.0 + r.nextDouble() * 16,
            ));
  }();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 400.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : 800.0;
        final t = animation.value;
        return Stack(clipBehavior: Clip.none, children: [
          for (final (i, (x, delay, speed, angle, size)) in _bits.indexed)
            () {
              final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
              if (local <= 0 || local >= 1) return const SizedBox.shrink();
              final double left;
              final double top;
              if (burst) {
                final d = local * speed * math.min(w, h) * 0.7;
                left = w / 2 + math.cos(angle) * d;
                top = h * 0.35 + math.sin(angle) * d + local * local * 120;
              } else {
                left = x * w + math.sin(local * 7 + angle) * 16;
                top = -30 + local * speed * (h + 60);
              }
              return Positioned(
                left: left,
                top: top,
                child: Opacity(
                  opacity: (1.2 - local).clamp(0.0, 1.0),
                  child: Text(emojis[i % emojis.length],
                      style: TextStyle(fontSize: size)),
                ),
              );
            }(),
        ]);
      }),
    );
  }
}

/// The signed-in player's own equipped looks, for places that show "you"
/// without a room view (home, victory effects). Set by AppState.
class MyLooks {
  static CosmeticLook? frame;
  static CosmeticLook? title;
  static CosmeticLook? effect;
}
