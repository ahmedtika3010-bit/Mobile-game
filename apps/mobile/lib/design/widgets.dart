import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import 'sfx.dart';
import 'tokens.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/* ------------------------------ background ------------------------------ */

/// The night-sky backdrop used by every screen: a deep gradient, two soft
/// lantern glows and slowly twinkling stars.
class NightBackground extends StatefulWidget {
  const NightBackground({super.key, required this.child, this.glow});
  final Widget child;

  /// Optional accent for the lower glow (e.g. the current game's colour).
  final Color? glow;

  @override
  State<NightBackground> createState() => _NightBackgroundState();
}

class _NightBackgroundState extends State<NightBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SkyPainter(_c, widget.glow ?? Tokens.pink),
        child: widget.child,
      );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t, this.glow) : super(repaint: t);
  final Animation<double> t;
  final Color glow;
  static final _stars = () {
    final r = math.Random(7);
    return List.generate(
        46,
        (_) => (
              r.nextDouble(),
              r.nextDouble() * 0.75,
              0.6 + r.nextDouble() * 1.6,
              r.nextDouble()
            ));
  }();

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Tokens.nightDeep, Tokens.night, Tokens.plum],
            stops: [0, 0.55, 1],
          ).createShader(rect));
    void glowAt(Offset c, double r, Color col, double a) => canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
                  colors: [col.withValues(alpha: a), col.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    glowAt(Offset(s.width * 0.85, s.height * 0.08), s.width * 0.55, Tokens.sun,
        0.16);
    glowAt(Offset(s.width * 0.1, s.height * 0.95), s.width * 0.8, glow, 0.22);
    final star = Paint()..color = Colors.white;
    for (final (x, y, r, phase) in _stars) {
      final tw =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((t.value + phase) * 2 * math.pi));
      star.color = Colors.white.withValues(alpha: 0.55 * tw);
      canvas.drawCircle(Offset(x * s.width, y * s.height), r, star);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.glow != glow;
}

/// Scaffold with the night background behind a transparent app bar.
class NightScaffold extends StatelessWidget {
  const NightScaffold(
      {super.key,
      required this.body,
      this.title,
      this.actions,
      this.glow,
      this.showBack = true,
      this.bottom});
  final Widget body;
  final Widget? title;
  final List<Widget>? actions;
  final Color? glow;
  final bool showBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Tokens.nightDeep,
      body: NightBackground(
        glow: glow,
        child: SafeArea(
          bottom: bottom == null,
          child: Column(children: [
            if (canPop || title != null || actions != null)
              SizedBox(
                height: 56,
                child: NavigationToolbar(
                  leading: canPop
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: Tokens.s8),
                          child: RoundIconButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              onPressed: () =>
                                  Navigator.of(context).maybePop()),
                        )
                      : null,
                  middle: title == null
                      ? null
                      : DefaultTextStyle.merge(
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                          child: title!),
                  trailing: actions == null
                      ? null
                      : Padding(
                          padding:
                              const EdgeInsetsDirectional.only(end: Tokens.s8),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions!),
                        ),
                ),
              ),
            Expanded(child: body),
            if (bottom != null) bottom!,
          ]),
        ),
      ),
    );
  }
}

/* -------------------------------- buttons -------------------------------- */

/// Chunky, tactile 3D game button: a bright face on a darker edge that
/// presses down when touched.
class GameButton extends StatefulWidget {
  const GameButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.color = Tokens.grape,
      this.icon,
      this.expand = true,
      this.busy = false,
      this.size = GameButtonSize.large,
      this.leading});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool expand;
  final bool busy;
  final GameButtonSize size;

  /// Custom leading widget (e.g. a brand logo) instead of [icon].
  final Widget? leading;

  @override
  State<GameButton> createState() => _GameButtonState();
}

enum GameButtonSize { medium, large }

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final face = enabled ? widget.color : const Color(0xFF453A6E);
    final edge = Tokens.shade(face, 0.18);
    final fg = enabled ? Tokens.onColor(widget.color) : Tokens.textFaint;
    final depth = widget.size == GameButtonSize.large ? 6.0 : 4.0;
    final pad = widget.size == GameButtonSize.large
        ? const EdgeInsets.symmetric(horizontal: Tokens.s24, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: Tokens.s16, vertical: 10);
    final fontSize = widget.size == GameButtonSize.large ? 20.0 : 17.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.selectionClick();
                Sfx.play('tap', volume: 0.4);
                widget.onPressed!();
              }
            : null,
        child: Padding(
          padding: EdgeInsets.only(top: _down ? depth : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: widget.expand ? double.infinity : null,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Tokens.r20),
              color: edge,
              boxShadow: [
                if (enabled && !_down)
                  BoxShadow(
                      color: face.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8)),
              ],
            ),
            padding: EdgeInsets.only(bottom: _down ? 0 : depth),
            child: Container(
              padding: pad,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Tokens.r20),
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Tokens.tint(face, 0.06), face]),
                border: Border.all(
                    color:
                        Colors.white.withValues(alpha: enabled ? 0.22 : 0.06),
                    width: 1.5),
              ),
              child: Row(
                mainAxisSize:
                    widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.busy)
                    SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: fg))
                  else if (widget.leading != null)
                    widget.leading!
                  else if (widget.icon != null)
                    Icon(widget.icon, color: fg, size: fontSize + 6),
                  if (widget.icon != null ||
                      widget.busy ||
                      widget.leading != null)
                    const SizedBox(width: Tokens.s8),
                  Flexible(
                    child: Text(widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontSize: fontSize,
                            height: 1.3,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small round glass button for toolbars.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(
      {super.key, required this.icon, required this.onPressed, this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: Tokens.glass,
          shape:
              const CircleBorder(side: BorderSide(color: Tokens.glassBorder)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
                dimension: 42,
                child: Icon(icon, color: Colors.white, size: 22)),
          ),
        ),
      );
}

/// Pressable wrapper that shrinks slightly while held.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key, required this.child, this.onTap, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: widget.onTap != null,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.onTap == null ? null : (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: widget.onTap == null
              ? null
              : (_) {
                  setState(() => _down = false);
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          child: AnimatedScale(
              scale: _down ? 0.96 : 1,
              duration: const Duration(milliseconds: 100),
              child: widget.child),
        ),
      );
}

/* -------------------------------- surfaces -------------------------------- */

class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(Tokens.s16),
      this.radius = Tokens.r24,
      this.color = Tokens.glass});
  final Widget child;
  final EdgeInsets padding;
  final Radius radius;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.all(radius),
          border: Border.all(color: Tokens.glassBorder, width: 1.2),
        ),
        child: child,
      );
}

class Pill extends StatelessWidget {
  const Pill(
      {super.key,
      required this.text,
      this.color = Tokens.sun,
      this.icon,
      this.solid = false,
      this.emoji});
  final String text;
  final Color color;
  final IconData? icon;
  final String? emoji;

  /// Solid pills use the colour as background; otherwise a tinted glass pill.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Tokens.onColor(color) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(99)),
        border: solid ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (emoji != null) ...[
          Text(emoji!, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5)
        ] else if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 5)
        ],
        Text(text,
            style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                height: 1.3)),
      ]),
    );
  }
}

/// Rounded square with a gradient and a big emoji: the icon of a game.
class GameIcon extends StatelessWidget {
  const GameIcon(
      {super.key, required this.emoji, required this.color, this.size = 64});
  final String emoji;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: Tokens.gradient(
              Tokens.tint(color, 0.12), Tokens.shade(color, 0.08)),
          borderRadius: BorderRadius.all(Radius.circular(size * 0.3)),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: size * 0.3,
                offset: Offset(0, size * 0.08))
          ],
        ),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.52)),
      );
}

/// App wordmark: a glowing crescent moon and the name in warm gradient.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
              dimension: size * 0.95,
              child: CustomPaint(painter: _MoonPainter())),
          SizedBox(width: size * 0.2),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
                    colors: [Tokens.sun, Tokens.orange, Tokens.pink])
                .createShader(r),
            child: Text(AppConfig.appName,
                style: TextStyle(
                    fontSize: size,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      );
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width * 0.42;
    canvas.drawCircle(
        c,
        r * 1.25,
        Paint()
          ..color = Tokens.sun.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    final moon = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final bite = Path()
      ..addOval(Rect.fromCircle(
          center: c.translate(-r * 0.55, -r * 0.25), radius: r * 0.85));
    canvas.drawPath(
        Path.combine(PathOperation.difference, moon, bite),
        Paint()
          ..shader = const LinearGradient(colors: [Tokens.sun, Tokens.orange])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c.translate(-r * 0.75, r * 0.55), r * 0.12,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* --------------------------------- motion --------------------------------- */

/// Fades and slides its child in after [delay]. Used to stagger lists.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn(
      {super.key,
      required this.child,
      this.delay = Duration.zero,
      this.offset = 24,
      this.duration = Tokens.slow});
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _c.value,
        child: Transform.translate(
            offset: Offset(0, (1 - _a.value) * widget.offset), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Gentle up-and-down float, for hero emoji and characters.
class Bob extends StatefulWidget {
  const Bob(
      {super.key,
      required this.child,
      this.amplitude = 6,
      this.period = const Duration(milliseconds: 2400),
      this.phase = 0});
  final Widget child;
  final double amplitude;
  final Duration period;
  final double phase;
  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
          offset: Offset(
              0,
              math.sin((_c.value + widget.phase) * 2 * math.pi) *
                  widget.amplitude),
          child: child),
      child: widget.child,
    );
  }
}

/// Springs its child in from small to full size (e.g. countdown numbers).
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.from = 0.4});
  final Widget child;
  final double from;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.elasticOut,
        builder: (_, s, c) => Transform.scale(scale: s, child: c),
        child: child,
      );
}

/// Shakes horizontally once when built (wrong answers).
class Shake extends StatelessWidget {
  const Shake({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    if (!enabled || _reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      builder: (_, t, c) => Transform.translate(
          offset: Offset(math.sin(t * math.pi * 6) * 8 * (1 - t), 0), child: c),
      child: child,
    );
  }
}

/// Counts a number up from zero.
class CountUp extends StatelessWidget {
  const CountUp(
      {super.key, required this.value, required this.style, this.prefix = ''});
  final int value;
  final TextStyle style;
  final String prefix;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('$prefix${v.round()}',
            textDirection: TextDirection.ltr, style: style),
      );
}

/// One burst of falling confetti.
class Confetti extends StatefulWidget {
  const Confetti({super.key});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(
        child: CustomPaint(painter: _ConfettiPainter(_c), size: Size.infinite));
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t) : super(repaint: t);
  final Animation<double> t;
  static final _bits = () {
    final r = math.Random(3);
    return List.generate(
        70,
        (i) => (
              r.nextDouble(), // x
              r.nextDouble() * 0.35, // start delay
              0.6 + r.nextDouble() * 0.6, // speed
              r.nextDouble() * math.pi * 2, // spin
              Tokens.choiceColors[i % Tokens.choiceColors.length],
              r.nextBool()
            ));
  }();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint();
    for (final (x, delay, speed, spin, color, round) in _bits) {
      final local = ((t.value - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final y = -20 + local * speed * (s.height + 60);
      final dx = math.sin(local * 8 + spin) * 18;
      p.color = color.withValues(alpha: (1 - local).clamp(0.0, 1.0) + 0.2);
      canvas.save();
      canvas.translate(x * s.width + dx, y);
      canvas.rotate(spin + local * 10);
      if (round) {
        canvas.drawCircle(Offset.zero, 4, p);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(-5, -3, 10, 6), const Radius.circular(2)),
            p);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* --------------------------------- timers --------------------------------- */

/// Circular countdown driven by server time (not frame count), so every
/// device shows the same remaining time.
class ServerTimerRing extends StatefulWidget {
  const ServerTimerRing(
      {super.key,
      required this.startsAt,
      required this.endsAt,
      required this.serverNow,
      this.size = 64});
  final int startsAt;
  final int endsAt;
  final int Function() serverNow;
  final double size;

  @override
  State<ServerTimerRing> createState() => _ServerTimerRingState();
}

class _ServerTimerRingState extends State<ServerTimerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(days: 1))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final total = (widget.endsAt - widget.startsAt).clamp(1, 1 << 31);
          final left = (widget.endsAt - widget.serverNow()).clamp(0, total);
          final f = left / total;
          final secs = (left / 1000).ceil();
          final color = f < 0.25
              ? Tokens.danger
              : f < 0.5
                  ? Tokens.orange
                  : Tokens.mint;
          final urgent = f < 0.25 && left > 0;
          return Semantics(
            label: '$secs',
            child: Transform.scale(
              scale: urgent
                  ? 1 +
                      0.06 *
                          math.sin(_c.value * 86400 * 2 * math.pi / 0.5).abs()
                  : 1,
              child: SizedBox.square(
                dimension: widget.size,
                child: CustomPaint(
                  painter: _RingPainter(f, color),
                  child: Center(
                    child: Text('$secs',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            fontSize: widget.size * 0.38)),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color);
  final double f;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 5;
    canvas.drawCircle(
        c, r + 4, Paint()..color = Tokens.nightDeep.withValues(alpha: 0.6));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.white.withValues(alpha: 0.12));
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.f != f || old.color != color;
}

/// Thin progress line for "question N of M".
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.index, required this.total});
  final int index;
  final int total;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: AnimatedContainer(
              duration: Tokens.medium,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i < index
                    ? Tokens.sun
                    : i == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.all(Radius.circular(99)),
              ),
            ),
          ),
      ]);
}

/// Page route with a soft fade + rise, matching the game feel.
class SoftRoute<T> extends PageRouteBuilder<T> {
  SoftRoute(Widget page)
      : super(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, a, __, child) {
            final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: c,
              child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                          .animate(c),
                  child: child),
            );
          },
        );
}
