import { describe, expect, it } from 'vitest';
import { Rng } from '../src/games/engine';
import { QUIZ_TIMING, quizModule, speedBonus } from '../src/games/quiz';

function content(n: number) {
  return Array.from({ length: n }, (_, i) => ({
    id: `q${i}`,
    category: 'general',
    difficulty: 'medium',
    payload: { prompt: `سؤال ${i}`, choices: ['أ', 'ب', 'ج', 'د'], correct: 0, explanation: null },
    acceptedAnswers: [],
  }));
}

function setup(players = ['a', 'b', 'c']) {
  const cfg = quizModule.validateConfig({ questionCount: 5, answerSeconds: 10 }, 'casual');
  const s = quizModule.setup(players, cfg, content(5), new Rng('seed-1'), 0);
  return { s, cfg };
}

const correctChoice = (s: ReturnType<typeof setup>['s']) => s.questions[s.index]!.correct;

describe('quiz module', () => {
  it('ranked always uses the standardized config', () => {
    const c = quizModule.validateConfig({ questionCount: 20, answerSeconds: 30, difficulty: 'easy' }, 'ranked');
    expect(c).toEqual({ category: 'mixed', difficulty: 'medium', questionCount: 10, answerSeconds: 15 });
  });

  it('shuffles choices identically for everyone and keeps the correct answer', () => {
    const { s } = setup();
    for (const q of s.questions) expect(q.choices[q.correct]).toBe('أ');
    const again = setup().s;
    expect(again.questions.map((q) => q.choices)).toEqual(s.questions.map((q) => q.choices));
  });

  it('never leaks the correct answer before the question closes', () => {
    const { s } = setup();
    const v = quizModule.viewFor(s, 'a', 0);
    expect(v.reveal).toBeNull();
    expect(JSON.stringify(v)).not.toContain('"correct"');
  });

  it('rejects early, late, duplicate and out-of-range answers', () => {
    const { s } = setup();
    const c = correctChoice(s);
    expect(quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: c }, 500)).toEqual({ ok: false, code: 'too_early' });
    expect(quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: 9 }, 1500)).toEqual({ ok: false, code: 'bad_choice' });
    expect(quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: c }, 1500).ok).toBe(true);
    expect(quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: c }, 1600)).toEqual({ ok: false, code: 'already_answered' });
    expect(quizModule.onAction(s, 'b', { kind: 'answer', questionIndex: 0, choice: c }, 11_500)).toEqual({ ok: false, code: 'too_late' });
    expect(quizModule.onAction(s, 'zzz', { kind: 'answer', questionIndex: 0, choice: c }, 1500)).toEqual({ ok: false, code: 'not_in_match' });
  });

  it('scores correctness first with a bounded, bucketed speed bonus', () => {
    expect(speedBonus(0, 10)).toBe(50);
    expect(speedBonus(999, 10)).toBe(50); // same bucket as instant
    expect(speedBonus(9_500, 10)).toBe(0);
    const { s } = setup(['a', 'b']);
    const c = correctChoice(s);
    quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: c }, 1_200);
    quizModule.onAction(s, 'b', { kind: 'answer', questionIndex: 0, choice: (c + 1) % 4 }, 1_100);
    quizModule.tick(s, 1_300, new Set(['a', 'b']));
    expect(s.stage).toBe('reveal');
    expect(s.lastPoints).toEqual({ a: QUIZ_TIMING.correctPoints + 50, b: 0 });
  });

  it('caps client latency compensation', () => {
    const { s } = setup(['a']);
    const c = correctChoice(s);
    // server measured 5s; client claims 0ms -> only 1.5s of compensation accepted
    quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: c, clientElapsedMs: 0 } as never, 6_000);
    expect(s.answers[0]!.get('a')!.elapsedMs).toBe(5_000 - QUIZ_TIMING.maxLatencyCompMs);
  });

  it('does not freeze when a player is disconnected and finishes after all questions', () => {
    const { s } = setup(['a', 'b']);
    let now = 0;
    for (let i = 0; i < 5; i++) {
      now = s.revealAt + 100;
      quizModule.onAction(s, 'a', { kind: 'answer', questionIndex: i, choice: correctChoice(s) }, now);
      // b is disconnected: only 'a' is active, so the question closes early
      quizModule.tick(s, now, new Set(['a']));
      expect(s.stage).toBe('reveal');
      now = s.revealEndsAt;
      quizModule.tick(s, now, new Set(['a']));
    }
    expect(quizModule.isFinished(s)).toBe(true);
    const r = quizModule.results(s);
    expect(r.ranking[0]).toMatchObject({ playerId: 'a', place: 1, correct: 5 });
    expect(r.ranking[1]).toMatchObject({ playerId: 'b', score: 0, place: 2 });
  });
});
