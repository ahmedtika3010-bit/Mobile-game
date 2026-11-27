import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A character's art. The designer's set (assets/characters) has one
/// picture per character; the personas (assets/personas, generated from
/// design/personas) have one per expression, marked by `{e}` in the path.
class ChibiArt {
  const ChibiArt(this.name, this.head, this.full, this.color);
  final String name;
  final String head;
  final String full;
  final Color color;

  String headFor(ChibiExpression e) => head.replaceFirst('{e}', e.name);
  String fullFor(ChibiExpression e) => full.replaceFirst('{e}', e.name);
}

const _personaColors = {
  'youssef': Color(0xFF8FB4FF),
  'nour': Color(0xFFFFB3CB),
  'karim': Color(0xFF7BE8C8),
  'layla': Color(0xFFFFD66B),
  'omar': Color(0xFFFF9A8A),
  'salma': Color(0xFFC3A6FF),
  'saber': Color(0xFFE8C9A0),
  'fatma': Color(0xFF7CD3E6),
  'khaled': Color(0xFFB5E07A),
  'reem': Color(0xFFFFB27A),
};

const _personaNames = {
  'youssef': 'يوسف',
  'nour': 'نور',
  'karim': 'كريم',
  'layla': 'ليلى',
  'omar': 'عمر',
  'salma': 'سلمى',
  'saber': 'عم صابر',
  'fatma': 'فاطمة',
  'khaled': 'خالد',
  'reem': 'ريم',
};

/// Player avatar: the designer's character portrait on a coloured badge.
/// Unknown ids fall back to a simple character drawn in code, so older or
/// future ids never break. Expressions apply to the drawn fallback only
/// until animated (Rive) versions exist.
class ChibiAvatar extends StatelessWidget {
  const ChibiAvatar(
      {super.key,
      required this.avatarId,
      this.size = 56,
      this.expression = ChibiExpression.happy,
      this.dimmed = false,
      this.badge = true});

  final String avatarId;
  final double size;
  final ChibiExpression expression;
  final bool dimmed;

  /// Draw the round coloured background behind the character.
  final bool badge;

  static final Map<String, ChibiArt> _art = {
    for (final id in _personaNames.keys)
      'chibi_p_$id': ChibiArt(
          _personaNames[id]!,
          'assets/personas/${id}_{e}_head.png',
          'assets/personas/${id}_{e}_full.png',
          _personaColors[id]!),
    'chibi_kairo': ChibiArt('كايرو', 'assets/characters/kairo_head.png',
        'assets/characters/kairo_full.png', Color(0xFF6FE0E6)),
    'chibi_sira': ChibiArt('سيرا', 'assets/characters/sira_head.png',
        'assets/characters/sira_full.png', Color(0xFFFFB37A)),
    'chibi_forest': ChibiArt('ورقة', 'assets/characters/forest_head.png',
        'assets/characters/forest_full.png', Color(0xFFB5E07A)),
    'chibi_rithia': ChibiArt('ريثيا', 'assets/characters/rithia_head.png',
        'assets/characters/rithia_full.png', Color(0xFFF09BEA)),
  };

  /// Ids used before the real characters existed map onto them.
  static const _legacy = {
    'chibi_base_1': 'chibi_kairo',
    'chibi_base_2': 'chibi_sira',
    'chibi_base_3': 'chibi_forest',
    'chibi_base_4': 'chibi_rithia',
  };

  /// Grown-up personas first, then the designer's original four.
  static const starterIds = [
    'chibi_p_youssef',
    'chibi_p_nour',
    'chibi_p_karim',
    'chibi_p_layla',
    'chibi_p_omar',
    'chibi_p_salma',
    'chibi_p_saber',
    'chibi_p_fatma',
    'chibi_p_khaled',
    'chibi_p_reem',
    'chibi_kairo',
    'chibi_sira',
    'chibi_forest',
    'chibi_rithia',
  ];

  static ChibiArt? artFor(String id) => _art[_legacy[id] ?? id];

  /// The avatar's signature colour (badge background).
  static Color colorFor(String id) =>
      artFor(id)?.color ??
      _ChibiPainter._badges[_hash(id) % _ChibiPainter._badges.length];

  static int _hash(String id) =>
      id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);

  @override
  Widget build(BuildContext context) {
    final art = artFor(avatarId);
    final Widget child = art == null
        ? SizedBox.square(
            dimension: size,
            child: CustomPaint(
                painter: _ChibiPainter(avatarId, expression, badge)))
        : _ArtBadge(
            art: art, image: art.headFor(expression), size: size, badge: badge);
    if (!dimmed) return child;
    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
          child: child),
    );
  }
}

enum ChibiExpression { happy, neutral, sad, surprised }

class _ArtBadge extends StatelessWidget {
  const _ArtBadge(
      {required this.art,
      required this.image,
      required this.size,
      required this.badge});
  final ChibiArt art;
  final String image;
  final double size;
  final bool badge;
  @override
  Widget build(BuildContext context) {
    final img = Image.asset(image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.2),
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.medium);
    if (!badge) return SizedBox.square(dimension: size, child: img);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [
          Tokens.tint(art.color, 0.08),
          Tokens.shade(art.color, 0.1)
        ]),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: size > 60 ? 3 : 2),
      ),
      child: ClipOval(child: img),
    );
  }
}

/// Full-body character art (for big moments: onboarding, sign-in, wins).
class ChibiFullBody extends StatelessWidget {
  const ChibiFullBody(
      {super.key,
      required this.avatarId,
      this.height = 200,
      this.expression = ChibiExpression.happy});
  final String avatarId;
  final double height;
  final ChibiExpression expression;
  @override
  Widget build(BuildContext context) {
    final art = ChibiAvatar.artFor(avatarId);
    if (art == null) {
      return ChibiAvatar(
          avatarId: avatarId, size: height * 0.7, expression: expression);
    }
    return Image.asset(art.fullFor(expression),
        height: height,
        fit: BoxFit.contain,
        cacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.medium);
  }
}

class _ChibiPainter extends CustomPainter {
  _ChibiPainter(this.id, this.expression, this.badge);
  final String id;
  final ChibiExpression expression;
  final bool badge;

  static const _skins = [
    Color(0xFFFFDDC2),
    Color(0xFFF3C48E),
    Color(0xFFD39A62),
    Color(0xFF9A6236)
  ];
  static const _hair = [
    Color(0xFF2B1A12),
    Color(0xFF6B3E26),
    Color(0xFF15131C),
    Color(0xFFB8622A),
    Color(0xFF4B2E83),
  ];
  static const _shirts = [
    Tokens.coral,
    Tokens.sky,
    Tokens.mint,
    Tokens.grape,
    Tokens.orange,
    Tokens.pink
  ];
  static const _badges = [
    Color(0xFFFFD66B),
    Color(0xFF7CC8FF),
    Color(0xFF7BE8C8),
    Color(0xFFC3A6FF),
    Color(0xFFFFA8C5),
    Color(0xFFFFB27A),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final h = ChibiAvatar._hash(id);
    final skin = _skins[h % _skins.length];
    final hair = _hair[(h ~/ 4) % _hair.length];
    final shirt = _shirts[(h ~/ 20) % _shirts.length];
    final style = (h ~/ 120) % 3; // hair style
    final w = s.width;

    if (badge) {
      final c = Offset(w / 2, w / 2);
      final bg = _badges[h % _badges.length];
      canvas.drawCircle(
          c,
          w / 2,
          Paint()
            ..shader = RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    colors: [Tokens.tint(bg, 0.08), Tokens.shade(bg, 0.08)])
                .createShader(Rect.fromCircle(center: c, radius: w / 2)));
      canvas.save();
      canvas
          .clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: w / 2)));
    }

    // body / shoulders
    final body = Path()
      ..moveTo(w * 0.2, w * 1.02)
      ..quadraticBezierTo(w * 0.22, w * 0.74, w * 0.5, w * 0.72)
      ..quadraticBezierTo(w * 0.78, w * 0.74, w * 0.8, w * 1.02)
      ..close();
    canvas.drawPath(body, Paint()..color = shirt);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.42, w * 0.73)
          ..quadraticBezierTo(w * 0.5, w * 0.8, w * 0.58, w * 0.73),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..color = Tokens.shade(shirt, 0.12));

    final headC = Offset(w / 2, w * 0.43);
    final headR = w * 0.27;

    // hair behind (long style)
    if (style == 2) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: headC.translate(0, w * 0.06),
                  width: headR * 2.3,
                  height: headR * 2.2),
              Radius.circular(headR)),
          Paint()..color = hair);
    }

    // ears
    final skinP = Paint()..color = skin;
    canvas.drawCircle(
        headC.translate(-headR * 0.98, w * 0.03), w * 0.05, skinP);
    canvas.drawCircle(headC.translate(headR * 0.98, w * 0.03), w * 0.05, skinP);
    // head
    canvas.drawOval(
        Rect.fromCenter(center: headC, width: headR * 2, height: headR * 1.92),
        skinP);

    // hair on top
    final hairP = Paint()..color = hair;
    final top = Path()
      ..moveTo(headC.dx - headR * 1.04, headC.dy + headR * 0.05)
      ..cubicTo(
          headC.dx - headR * 1.1,
          headC.dy - headR * 1.25,
          headC.dx + headR * 1.1,
          headC.dy - headR * 1.25,
          headC.dx + headR * 1.04,
          headC.dy + headR * 0.05);
    switch (style) {
      case 0: // side fringe
        top
          ..quadraticBezierTo(headC.dx + headR * 0.6, headC.dy - headR * 0.55,
              headC.dx - headR * 0.1, headC.dy - headR * 0.35)
          ..quadraticBezierTo(headC.dx - headR * 0.7, headC.dy - headR * 0.3,
              headC.dx - headR * 1.04, headC.dy + headR * 0.05);
      case 1: // spiky
        for (var i = 0; i < 4; i++) {
          final x0 = headC.dx + headR * (0.9 - i * 0.5);
          top.lineTo(x0 - headR * 0.25, headC.dy - headR * 0.3);
          top.lineTo(x0 - headR * 0.4, headC.dy - headR * 0.55);
        }
        top.lineTo(headC.dx - headR * 1.04, headC.dy + headR * 0.05);
      default: // long, centre part
        top
          ..quadraticBezierTo(headC.dx + headR * 0.5, headC.dy - headR * 0.5,
              headC.dx, headC.dy - headR * 0.6)
          ..quadraticBezierTo(headC.dx - headR * 0.5, headC.dy - headR * 0.5,
              headC.dx - headR * 1.04, headC.dy + headR * 0.05);
    }
    top.close();
    canvas.drawPath(top, hairP);
    // hair shine
    canvas.drawArc(
        Rect.fromCircle(
            center: headC.translate(-headR * 0.2, -headR * 0.15),
            radius: headR * 0.7),
        math.pi * 1.15,
        math.pi * 0.35,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w * 0.025
          ..color = Colors.white.withValues(alpha: 0.25));

    // eyes
    final ink = Paint()..color = Tokens.ink;
    final ey = headC.dy + headR * 0.18;
    final ex = headR * 0.42;
    if (expression == ChibiExpression.happy) {
      final p = Paint()
        ..color = Tokens.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..strokeCap = StrokeCap.round;
      for (final sx in [-ex, ex]) {
        canvas.drawArc(
            Rect.fromCircle(
                center: Offset(headC.dx + sx, ey + w * 0.01), radius: w * 0.04),
            math.pi * 1.1,
            math.pi * 0.8,
            false,
            p);
      }
    } else {
      for (final sx in [-ex, ex]) {
        final c = Offset(headC.dx + sx, ey);
        canvas.drawOval(
            Rect.fromCenter(center: c, width: w * 0.075, height: w * 0.095),
            ink);
        canvas.drawCircle(c.translate(-w * 0.012, -w * 0.018), w * 0.016,
            Paint()..color = Colors.white);
      }
    }

    // cheeks
    final blush = Paint()..color = Tokens.coral.withValues(alpha: 0.35);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(headC.dx - headR * 0.68, ey + w * 0.07),
            width: w * 0.09,
            height: w * 0.05),
        blush);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(headC.dx + headR * 0.68, ey + w * 0.07),
            width: w * 0.09,
            height: w * 0.05),
        blush);

    // mouth
    final mc = Offset(headC.dx, ey + w * 0.1);
    final mouth = Paint()
      ..color = Tokens.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.026
      ..strokeCap = StrokeCap.round;
    switch (expression) {
      case ChibiExpression.happy:
        canvas.drawPath(
            Path()
              ..moveTo(mc.dx - w * 0.06, mc.dy - w * 0.01)
              ..quadraticBezierTo(
                  mc.dx, mc.dy + w * 0.07, mc.dx + w * 0.06, mc.dy - w * 0.01)
              ..close(),
            Paint()..color = const Color(0xFF8A2E3B));
      case ChibiExpression.sad:
        canvas.drawArc(
            Rect.fromCenter(
                center: mc.translate(0, w * 0.03),
                width: w * 0.1,
                height: w * 0.06),
            math.pi,
            math.pi,
            false,
            mouth);
      case ChibiExpression.surprised:
        canvas.drawOval(
            Rect.fromCenter(center: mc, width: w * 0.05, height: w * 0.065),
            Paint()..color = const Color(0xFF8A2E3B));
      case ChibiExpression.neutral:
        canvas.drawArc(
            Rect.fromCenter(
                center: mc.translate(0, -w * 0.01),
                width: w * 0.08,
                height: w * 0.04),
            0.2,
            math.pi - 0.4,
            false,
            mouth);
    }

    if (badge) canvas.restore();
  }

  @override
  bool shouldRepaint(_ChibiPainter old) =>
      old.id != id || old.expression != expression || old.badge != badge;
}
