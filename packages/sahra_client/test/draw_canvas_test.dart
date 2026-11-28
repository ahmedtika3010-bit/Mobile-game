import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('applies stream chunks in order and asks to resync after a gap', () {
    final c = DrawCanvas();
    expect(
        c.apply('t1', 0, [
          {
            't': 'b',
            'c': 1,
            'w': 0,
            'p': [0, 0, 10, 10]
          }
        ]),
        isTrue);
    expect(
        c.apply('t1', 1, [
          {
            't': 'p',
            'p': [20, 20]
          }
        ]),
        isTrue);
    expect(
        c.apply('t1', 5, [
          const {'t': 'x'}
        ]),
        isFalse); // missed chunks
    // The room resends the whole drawing from 0 with the same key.
    expect(
        c.apply('t1', 0, [
          {
            't': 'b',
            'c': 1,
            'w': 0,
            'p': [0, 0, 10, 10]
          }
        ]),
        isTrue);
    expect(c.ops, hasLength(1));
    // A new turn starts over.
    expect(c.apply('t2', 0, const []), isTrue);
    expect(c.ops, isEmpty);
  });

  test('replays strokes with undo and clear', () {
    List<double> pts(List<DrawStroke> s) => s.expand((x) => x.points).toList();
    final ops = <Map<String, dynamic>>[
      {
        't': 'b',
        'c': 0,
        'w': 1,
        'p': [1, 1]
      },
      {
        't': 'p',
        'p': [2, 2]
      },
      {
        't': 'b',
        'c': 2,
        'w': 0,
        'p': [5, 5]
      },
      {'t': 'u'},
    ];
    final strokes = DrawCanvas.strokesOf(ops);
    expect(strokes, hasLength(1));
    expect(pts(strokes), [1, 1, 2, 2]);
    expect(
        DrawCanvas.strokesOf([
          ...ops,
          {'t': 'x'}
        ]),
        isEmpty);
  });
}
