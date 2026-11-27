/** Guess with Emoji rules: same puzzles for all, typed answers, private guesses, content checks. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { EMOJI_MAX_GUESSES, usesNewerEmoji } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import type { ContentRow } from '../src/games/engine';
import { Rng } from '../src/games/engine';
import { answerShape, emojiModule as emoji, emojiPayloadSchema, type EmojiState } from '../src/games/emoji';

const bank = JSON.parse(readFileSync(join(__dirname, '../prisma/content/emoji_ar_v1.json'), 'utf8')) as {
  category: string; difficulty: string; emojis: string; answer: string; wrong: string[]; accepted: string[];
}[];
const content: ContentRow[] = bank.slice(0, 12).map((q, i) => ({
  id: `e${i}`,
  category: q.category,
  difficulty: q.difficulty,
  acceptedAnswers: [],
  payload: { emojis: q.emojis, answer: q.answer, wrong: q.wrong, accepted: q.accepted },
}));
const players = ['a', 'b', 'c'];
const all = new Set(players);
const game = (config: object, mode: 'private' | 'casual' | 'ranked' = 'private') =>
  emoji.setup(players, emoji.validateConfig(config, mode), content, new Rng('seed'), 0);
const shown = (s: EmojiState) => s.revealAt + 100;

describe('guess with emoji', () => {
  it('uses multiple choice outside private rooms, whatever the settings say', () => {
    expect(emoji.validateConfig({ answerMode: 'typed', questionCount: 5 }, 'ranked')).toMatchObject({ answerMode: 'choices', questionCount: 10 });
    expect(emoji.validateConfig({ answerMode: 'typed' }, 'casual').answerMode).toBe('choices');
    expect(emoji.validateConfig({ answerMode: 'typed' }, 'private')).toMatchObject({ answerMode: 'typed', answerSeconds: 30 });
  });

  it('scores choices like the quiz and hides the answer until the reveal', () => {
    const s = game({ questionCount: 5 });
    const q = s.puzzles[0]!;
    const v = emoji.viewFor(s, 'a', 0);
    expect(v.question!.emojis).toBe(q.emojis);
    expect(v.question!.choices).toHaveLength(4);
    expect(JSON.stringify(v)).not.toContain('"correct"');
    expect(v.reveal).toBeNull();
    const t = shown(s);
    expect(emoji.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: q.correct }, t)).toEqual({ ok: true });
    expect(emoji.onAction(s, 'b', { kind: 'answer', questionIndex: 0, choice: (q.correct + 1) % 4 }, t)).toEqual({ ok: true });
    expect(emoji.onAction(s, 'b', { kind: 'guess', questionIndex: 0, text: q.answer }, t)).toEqual({ ok: false, code: 'already_answered' });
    emoji.tick(s, s.deadline, all);
    const r = emoji.viewFor(s, 'c', 0).reveal!;
    expect(r.answer).toBe(q.answer);
    expect(r.points.a).toBeGreaterThanOrEqual(100);
    expect(r.points.b).toBe(0);
  });

  it('accepts approved spellings in typed mode and keeps guesses private', () => {
    const s = game({ questionCount: 5, answerMode: 'typed' });
    const q = s.puzzles[0]!;
    const t = shown(s);
    expect(emoji.viewFor(s, 'a', t).question!.choices).toEqual([]);
    expect(emoji.onAction(s, 'a', { kind: 'answer', questionIndex: 0, choice: 0 }, t)).toEqual({ ok: false, code: 'bad_action' });
    expect(emoji.onAction(s, 'b', { kind: 'guess', questionIndex: 0, text: 'إجابة غلط خالص' }, t)).toEqual({ ok: true });
    expect(emoji.viewFor(s, 'b', t).yourGuesses).toEqual(['إجابة غلط خالص']);
    expect(JSON.stringify(emoji.viewFor(s, 'a', t))).not.toContain('إجابة غلط');
    // Diacritics, hamza and the article do not matter.
    const variant = q.answer.replace(/^ال/, '').replace(/[أإآ]/g, 'ا');
    expect(emoji.onAction(s, 'a', { kind: 'guess', questionIndex: 0, text: ` ${variant} ` }, t)).toEqual({ ok: true });
    expect(emoji.viewFor(s, 'a', t)).toMatchObject({ yourChoice: q.correct, answeredCount: 1 });
  });

  it('allows only a few wrong guesses, and ends the puzzle when everyone is done', () => {
    const s = game({ questionCount: 5, answerMode: 'typed' });
    const t = shown(s);
    for (let i = 0; i < EMOJI_MAX_GUESSES; i++) emoji.onAction(s, 'a', { kind: 'guess', questionIndex: 0, text: `غلط ${i}` }, t);
    expect(emoji.onAction(s, 'a', { kind: 'guess', questionIndex: 0, text: 'تاني' }, t)).toEqual({ ok: false, code: 'no_guesses_left' });
    emoji.onAction(s, 'b', { kind: 'guess', questionIndex: 0, text: s.puzzles[0]!.answer }, t);
    emoji.tick(s, t, new Set(['a', 'b']));
    expect(s.stage).toBe('reveal');
  });

  it('shows the answer shape at half time in typed mode', () => {
    const s = game({ questionCount: 5, answerMode: 'typed' });
    expect(emoji.viewFor(s, 'a', 0).question!.hint).toBeNull();
    expect(emoji.nextWakeAt(s)).toBe(s.hintAt);
    emoji.tick(s, s.hintAt, all);
    expect(emoji.viewFor(s, 'a', 0).question!.hint).toBe(answerShape(s.puzzles[0]!.answer));
    expect(emoji.nextWakeAt(s)).toBe(s.deadline);
    expect(answerShape('الأسد الملك')).toBe('•••••  •••••');
  });

  it('plays to the end and ranks by score', () => {
    const s = game({ questionCount: 5 });
    while (s.stage !== 'finished') {
      if (s.stage === 'question') {
        emoji.onAction(s, 'a', { kind: 'answer', questionIndex: s.index, choice: s.puzzles[s.index]!.correct }, shown(s));
        emoji.tick(s, s.deadline, all);
      } else emoji.tick(s, s.revealEndsAt, all);
    }
    const res = emoji.results(s);
    expect(res.ranking[0]).toMatchObject({ playerId: 'a', place: 1, correct: 5 });
    expect(emoji.viewFor(s, 'b', 0).final!.ranking).toHaveLength(3);
  });

  it('ships a valid bank that every phone can draw', () => {
    expect(bank.length).toBeGreaterThanOrEqual(80);
    for (const d of ['easy', 'medium', 'hard']) expect(bank.filter((q) => q.difficulty === d).length).toBeGreaterThanOrEqual(15);
    const seen = new Set<string>();
    for (const q of bank) {
      expect(emojiPayloadSchema.safeParse(q).success, q.answer).toBe(true);
      expect(usesNewerEmoji(q.emojis), q.emojis).toBe(false);
      expect(seen.has(q.emojis), q.emojis).toBe(false);
      seen.add(q.emojis);
    }
    expect(usesNewerEmoji('🧊')).toBe(true);
    expect(emojiPayloadSchema.safeParse({ emojis: 'أسد 🦁', answer: 'الأسد', wrong: ['النمر', 'الفهد', 'الذئب'] }).success).toBe(false);
  });
});
