import 'dart:io';

import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('the move library matches the server one', () {
    final ts = File('../shared/src/acting.ts').readAsStringSync();
    final ids = RegExp(r"m\('(\w+)', '(\w+)'")
        .allMatches(ts)
        .map((m) => m.group(1))
        .toList();
    expect(ids, isNotEmpty);
    expect(actMoves.map((m) => m.id).toList(), ids);
  });
}
