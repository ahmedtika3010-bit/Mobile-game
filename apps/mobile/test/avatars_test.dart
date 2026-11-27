import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahra/design/chibi_avatar.dart';

void main() {
  test('every starter character has its art, for every expression', () {
    expect(ChibiAvatar.starterIds.length, greaterThanOrEqualTo(14));
    for (final id in ChibiAvatar.starterIds) {
      expect(RegExp(r'^chibi_[a-z0-9_]{1,32}$').hasMatch(id), isTrue,
          reason: '$id must pass the server avatar check');
      final art = ChibiAvatar.artFor(id);
      expect(art, isNotNull, reason: id);
      for (final e in ChibiExpression.values) {
        for (final path in [art!.headFor(e), art.fullFor(e)]) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    }
  });
}
