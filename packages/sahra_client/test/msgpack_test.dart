import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips JSON-like values including Arabic text', () {
    final value = {
      'type': 'answer',
      'n': 300,
      'neg': -5,
      'big': 1764160000000,
      'u32': 4000000000,
      'i32': -70000,
      'f': 1.5,
      'ok': true,
      'nil': null,
      'text': 'ما عاصمة مصر؟' * 3,
      'list': [1, 'ب', false],
    };
    final w = MsgPackWriter()..write(value);
    final back = MsgPackReader(w.takeBytes()).read() as Map;
    expect(back.keys, value.keys);
    for (final k in value.keys) {
      expect(back[k], value[k], reason: k);
    }
  });
}
