import 'package:flutter/material.dart';

import 'tokens.dart';

/// Chunky, tactile game button with a pressed-down animation.
class GameButton extends StatefulWidget {
  const GameButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.color = Tokens.grape,
      this.icon,
      this.expand = true,
      this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool expand;
  final bool busy;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final base = enabled ? widget.color : widget.color.withValues(alpha: 0.4);
    final shade = HSLColor.fromColor(base)
        .withLightness((HSLColor.fromColor(base).lightness - 0.15).clamp(0, 1))
        .toColor();
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onPressed!();
              }
            : null,
        child: AnimatedContainer(
          duration: Tokens.fast,
          margin: EdgeInsets.only(top: _down ? 4 : 0),
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s24, vertical: Tokens.s16),
          width: widget.expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: base,
            borderRadius: const BorderRadius.all(Tokens.r16),
            boxShadow: _down
                ? const []
                : [BoxShadow(color: shade, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.busy)
                const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
              else if (widget.icon != null)
                Icon(widget.icon, color: Colors.white),
              if (widget.icon != null || widget.busy)
                const SizedBox(width: Tokens.s8),
              Flexible(
                child: Text(widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(
      {super.key, required this.text, this.color = Tokens.grape, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: const BorderRadius.all(Radius.circular(99))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4)
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

/// Shrinking time bar driven by server time (not by frame count), so every
/// device shows the same remaining time.
class ServerTimerBar extends StatefulWidget {
  const ServerTimerBar(
      {super.key,
      required this.startsAt,
      required this.endsAt,
      required this.serverNow,
      this.color = Tokens.sun});
  final int startsAt;
  final int endsAt;
  final int Function() serverNow;
  final Color color;

  @override
  State<ServerTimerBar> createState() => _ServerTimerBarState();
}

class _ServerTimerBarState extends State<ServerTimerBar>
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
          return Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(99)),
                child: LinearProgressIndicator(
                  value: f,
                  minHeight: 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  color: f < 0.25 ? Tokens.coral : widget.color,
                ),
              ),
            ),
            const SizedBox(width: Tokens.s12),
            SizedBox(
              width: 28,
              child: Text('$secs',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ),
          ]);
        },
      );
}
