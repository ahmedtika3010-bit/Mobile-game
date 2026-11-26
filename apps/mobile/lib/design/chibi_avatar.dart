import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// PLACEHOLDER Chibi avatar drawn in code (big head, small body).
/// The final characters will be Rive files from an artist; this keeps the
/// same API (avatarId, expression, size) so screens do not change.
class ChibiAvatar extends StatelessWidget {
  const ChibiAvatar(
      {super.key,
      required this.avatarId,
      this.size = 56,
      this.expression = ChibiExpression.happy,
      this.dimmed = false});

  final String avatarId;
  final double size;
  final ChibiExpression expression;
  final bool dimmed;

  static const starterIds = [
    'chibi_base_1',
    'chibi_base_2',
    'chibi_base_3',
    'chibi_base_4'
  ];

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _ChibiPainter(avatarId, expression))),
    );
  }
}

enum ChibiExpression { happy, neutral, sad, surprised }

class _ChibiPainter extends CustomPainter {
  _ChibiPainter(this.id, this.expression);
  final String id;
  final ChibiExpression expression;

  static const _skins = [
    Color(0xFFFFD9B8),
    Color(0xFFF1C27D),
    Color(0xFFC68642),
    Color(0xFF8D5524)
  ];
  static const _hair = [
    Color(0xFF2D1B12),
    Color(0xFF6B3E26),
    Color(0xFF1B1B1B),
    Color(0xFFB5651D)
  ];
  static const _shirts = [Tokens.coral, Tokens.sky, Tokens.mint, Tokens.grape];

  @override
  void paint(Canvas canvas, Size s) {
    final h = id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final skin = _skins[h % 4],
        hair = _hair[(h ~/ 4) % 4],
        shirt = _shirts[(h ~/ 16) % 4];
    final w = s.width;
    // body
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.3, w * 0.68, w * 0.4, w * 0.3),
        Radius.circular(w * 0.12));
    canvas.drawRRect(body, Paint()..color = shirt);
    // head
    final headC = Offset(w / 2, w * 0.4);
    final headR = w * 0.34;
    canvas.drawCircle(headC, headR, Paint()..color = skin);
    // hair cap
    canvas.drawArc(Rect.fromCircle(center: headC, radius: headR), math.pi,
        math.pi, true, Paint()..color = hair);
    // eyes
    final eye = Paint()..color = Tokens.ink;
    final ey = w * 0.44;
    if (expression == ChibiExpression.happy) {
      final p = Paint()
        ..color = Tokens.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.4, ey), radius: w * 0.04),
          math.pi,
          math.pi,
          false,
          p);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.6, ey), radius: w * 0.04),
          math.pi,
          math.pi,
          false,
          p);
    } else {
      canvas.drawCircle(Offset(w * 0.4, ey), w * 0.04, eye);
      canvas.drawCircle(Offset(w * 0.6, ey), w * 0.04, eye);
    }
    // mouth
    final mouth = Paint()
      ..color = Tokens.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    final mc = Offset(w / 2, w * 0.56);
    switch (expression) {
      case ChibiExpression.happy:
        canvas.drawArc(
            Rect.fromCenter(center: mc, width: w * 0.16, height: w * 0.1),
            0,
            math.pi,
            false,
            mouth);
      case ChibiExpression.sad:
        canvas.drawArc(
            Rect.fromCenter(
                center: mc.translate(0, w * 0.04),
                width: w * 0.14,
                height: w * 0.08),
            math.pi,
            math.pi,
            false,
            mouth);
      case ChibiExpression.surprised:
        canvas.drawCircle(mc, w * 0.035, mouth);
      case ChibiExpression.neutral:
        canvas.drawLine(
            mc.translate(-w * 0.05, 0), mc.translate(w * 0.05, 0), mouth);
    }
    // cheeks
    final blush = Paint()..color = Tokens.coral.withValues(alpha: 0.35);
    canvas.drawCircle(Offset(w * 0.3, w * 0.52), w * 0.04, blush);
    canvas.drawCircle(Offset(w * 0.7, w * 0.52), w * 0.04, blush);
  }

  @override
  bool shouldRepaint(_ChibiPainter old) =>
      old.id != id || old.expression != expression;
}
