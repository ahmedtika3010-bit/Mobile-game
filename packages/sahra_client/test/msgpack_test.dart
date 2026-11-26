import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips JSON-like values including Arabic text', () {
    final value = {
      'type': 'answer',
      'n': 300,
      'neg': -5,
      'big': 1764160000000,
      'f': 1.5,
      'ok': true,
      'nil': null,
      'text': 'ما عاصمة مصر؟' * 3,
      'list': [1, 'ب', false],
    };
    final w = MsgPackWriter()..write(value);
    final back = MsgPackReader(w.takeBytes()).read();
    expect(back, value);
  });
}
