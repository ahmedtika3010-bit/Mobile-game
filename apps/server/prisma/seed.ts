/**
 * Quiz content for a local build. Nothing here is playable until a human
 * approves it in the admin panel:
 *  - a few developer-written samples, inserted as `in_review`;
 *  - the question bank in prisma/content/quiz_ar_v1.csv (admin CSV format).
 *    It was drafted with AI help, so it is inserted as `in_review` with
 *    source `ai_suggested` and must be fact-checked before release.
 * Spy packs (prisma/content/spy_ar_v1.json: words + approved questions per
 * category), Liar question pairs (prisma/content/liar_ar_v1.json) and Who Among Us
 * questions (prisma/content/who_ar_v1.json) and emoji puzzles
 * (prisma/content/emoji_ar_v1.json) and the Stop dictionary
 * (prisma/content/stop_ar_v1.json) and Draw and Guess words
 * (prisma/content/draw_ar_v1.json) and Football Challenges items
 * (prisma/content/football_ar_v1.json, each with the date its facts hold) follow
 * the same rule: AI-assisted, `in_review` until approved.
 * For local testing only, `npm run db:seed -- --approve-for-local-testing`
 * approves everything directly. Re-running only adds questions whose prompt
 * is not in the database yet.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'csv-parse/sync';
import { prisma } from '../src/db';

type Q = [category: string, difficulty: string, prompt: string, choices: string[], explanation?: string];

// The first choice is the correct one; choices are shuffled per match.
const QUESTIONS: Q[] = [
  ['geography', 'easy', 'ما عاصمة اليابان؟', ['طوكيو', 'أوساكا', 'كيوتو', 'ناغويا']],
  ['geography', 'easy', 'ما أطول نهر في قارة أفريقيا؟', ['النيل', 'الكونغو', 'النيجر', 'الزامبيزي']],
  ['geography', 'easy', 'ما عاصمة المغرب؟', ['الرباط', 'الدار البيضاء', 'مراكش', 'فاس']],
  ['geography', 'easy', 'ما أكبر محيط في العالم؟', ['المحيط الهادئ', 'المحيط الأطلسي', 'المحيط الهندي', 'المحيط المتجمد الشمالي']],
  ['geography', 'medium', 'ما أصغر دولة في العالم من حيث المساحة؟', ['الفاتيكان', 'موناكو', 'سان مارينو', 'مالطا']],
  ['geography', 'medium', 'ما عاصمة أستراليا؟', ['كانبرا', 'سيدني', 'ملبورن', 'بيرث']],
  ['geography', 'medium', 'ما أكبر صحراء حارة في العالم؟', ['الصحراء الكبرى', 'صحراء الربع الخالي', 'صحراء كالاهاري', 'صحراء غوبي']],
  ['science', 'easy', 'ما أكبر كوكب في المجموعة الشمسية؟', ['المشتري', 'زحل', 'أورانوس', 'نبتون']],
  ['science', 'medium', 'ما الرمز الكيميائي للذهب؟', ['Au', 'Ag', 'Fe', 'Gd']],
  ['science', 'medium', 'كم تبلغ سرعة الضوء في الفراغ تقريباً؟', ['300 ألف كم في الثانية', '30 ألف كم في الثانية', '3 ملايين كم في الثانية', '3 آلاف كم في الثانية']],
  ['science', 'medium', 'كم عدد عظام جسم الإنسان البالغ عادةً؟', ['206', '201', '212', '196']],
  ['science', 'medium', 'ما الغاز الأكثر وفرة في الغلاف الجوي للأرض؟', ['النيتروجين', 'الأكسجين', 'ثاني أكسيد الكربون', 'الأرجون']],
  ['sports', 'easy', 'كم عدد لاعبي فريق كرة القدم داخل الملعب؟', ['11', '10', '9', '12']],
  ['sports', 'easy', 'كم دقيقة تستمر مباراة كرة القدم الرسمية بدون وقت إضافي؟', ['90', '80', '100', '60']],
  ['history', 'easy', 'في أي سنة انتهت الحرب العالمية الثانية؟', ['1945', '1939', '1918', '1950']],
  ['history', 'medium', 'لأي ملك يُنسب بناء الهرم الأكبر في الجيزة؟', ['خوفو', 'خفرع', 'منقرع', 'رمسيس الثاني']],
  ['history', 'medium', 'في أي سنة حصل نجيب محفوظ على جائزة نوبل في الأدب؟', ['1988', '1978', '1994', '1980']],
  ['entertainment', 'medium', 'من مؤلف كتاب "الأيام"؟', ['طه حسين', 'نجيب محفوظ', 'عباس العقاد', 'توفيق الحكيم']],
  ['general', 'easy', 'كم عدد أضلاع الشكل السداسي؟', ['6', '5', '8', '7']],
  ['general', 'easy', 'كم عدد أيام السنة الميلادية الكبيسة؟', ['366', '365', '364', '367']],
];

type Row = { category: string; difficulty: string; prompt: string; choices: string[]; correct: number; explanation: string | null; source: 'human' | 'ai_suggested' };

const COLUMNS = ['category', 'difficulty', 'prompt', 'choice1', 'choice2', 'choice3', 'choice4', 'correct', 'explanation'] as const;

function loadBank(): Row[] {
  const csv = readFileSync(join(__dirname, 'content', 'quiz_ar_v1.csv'), 'utf8');
  const rows: Record<(typeof COLUMNS)[number], string>[] = parse(csv, { columns: true, skip_empty_lines: true, trim: true, bom: true });
  return rows.map((r) => ({
    category: r.category,
    difficulty: r.difficulty,
    prompt: r.prompt,
    choices: [r.choice1, r.choice2, r.choice3, r.choice4].filter(Boolean),
    correct: Number(r.correct) - 1,
    explanation: r.explanation || null,
    source: 'ai_suggested' as const,
  }));
}

type SpyPackFile = { category: string; words: string[]; questions: string[] }[];

async function seedSpy(approve: boolean) {
  const packs: SpyPackFile = JSON.parse(readFileSync(join(__dirname, 'content', 'spy_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'spy' }, select: { category: true } });
  const have = new Set(existing.map((e) => e.category));
  const fresh = packs.filter((p) => !have.has(p.category));
  if (fresh.length === 0) return console.log(`spy content up to date (${existing.length} packs)`);
  await prisma.contentItem.createMany({
    data: fresh.map((p) => ({
      gameId: 'spy',
      category: p.category,
      difficulty: 'medium',
      payload: { words: p.words, questions: p.questions },
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} spy packs as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

type LiarPairFile = { category: string; difficulty: string; main: string; odd: string; options: string[] }[];

async function seedLiar(approve: boolean) {
  const pairs: LiarPairFile = JSON.parse(readFileSync(join(__dirname, 'content', 'liar_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'liar' }, select: { payload: true } });
  const have = new Set(existing.map((e) => (e.payload as { main?: string }).main));
  const fresh = pairs.filter((p) => !have.has(p.main));
  if (fresh.length === 0) return console.log(`liar content up to date (${existing.length} pairs)`);
  await prisma.contentItem.createMany({
    data: fresh.map((p) => ({
      gameId: 'liar',
      category: p.category,
      difficulty: p.difficulty,
      payload: { main: p.main, odd: p.odd, options: p.options },
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} liar pairs as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

async function seedWho(approve: boolean) {
  const items: { category: string; text: string }[] = JSON.parse(readFileSync(join(__dirname, 'content', 'who_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'who' }, select: { payload: true } });
  const have = new Set(existing.map((e) => (e.payload as { text?: string }).text));
  const fresh = items.filter((q) => !have.has(q.text));
  if (fresh.length === 0) return console.log(`who content up to date (${existing.length} questions)`);
  await prisma.contentItem.createMany({
    data: fresh.map((q) => ({
      gameId: 'who',
      category: q.category,
      difficulty: 'medium',
      payload: { text: q.text },
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} who questions as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

type EmojiFile = { category: string; difficulty: string; emojis: string; answer: string; wrong: string[]; accepted: string[] }[];

async function seedEmoji(approve: boolean) {
  const items: EmojiFile = JSON.parse(readFileSync(join(__dirname, 'content', 'emoji_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'emoji' }, select: { payload: true } });
  const have = new Set(existing.map((e) => (e.payload as { emojis?: string }).emojis));
  const fresh = items.filter((q) => !have.has(q.emojis));
  if (fresh.length === 0) return console.log(`emoji content up to date (${existing.length} puzzles)`);
  await prisma.contentItem.createMany({
    data: fresh.map((q) => ({
      gameId: 'emoji',
      category: q.category,
      difficulty: q.difficulty,
      payload: { emojis: q.emojis, answer: q.answer, wrong: q.wrong, accepted: q.accepted },
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} emoji puzzles as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

async function seedStop(approve: boolean) {
  const lists: { category: string; words: string[] }[] = JSON.parse(readFileSync(join(__dirname, 'content', 'stop_ar_v1.json'), 'utf8'));
  // One dictionary item per category; re-running adds only categories that are missing.
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'stop', source: 'ai_suggested' }, select: { category: true } });
  const have = new Set(existing.map((e) => e.category));
  const fresh = lists.filter((l) => !have.has(l.category));
  if (fresh.length === 0) return console.log(`stop dictionary up to date (${existing.length} categories)`);
  await prisma.contentItem.createMany({
    data: fresh.map((l) => ({
      gameId: 'stop',
      category: l.category,
      difficulty: 'medium',
      payload: { words: l.words },
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} stop dictionary lists as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

type DrawFile = { category: string; difficulty: string; word: string; accepted: string[]; sketch?: unknown }[];

async function seedDraw(approve: boolean) {
  const items: DrawFile = JSON.parse(readFileSync(join(__dirname, 'content', 'draw_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'draw' }, select: { payload: true } });
  const have = new Set(existing.map((e) => (e.payload as { word?: string }).word));
  const fresh = items.filter((w) => !have.has(w.word));
  if (fresh.length === 0) return console.log(`draw content up to date (${existing.length} words)`);
  await prisma.contentItem.createMany({
    data: fresh.map((w) => ({
      gameId: 'draw',
      category: w.category,
      difficulty: w.difficulty,
      payload: { word: w.word, accepted: w.accepted, ...(w.sketch ? { sketch: w.sketch } : {}) } as object,
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} draw words as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

type FootballFile = { category: string; difficulty: string; payload: { mode: string; answer: string; asOf: string } & Record<string, unknown> }[];

/** Identity of a football item, so re-seeding never duplicates one. */
function footballKey(p: Record<string, unknown>) {
  return JSON.stringify([p.mode, p.prompt ?? p.answer, p.from ?? null, p.when ?? null, p.clubs ?? null]);
}

async function seedFootball(approve: boolean) {
  const items: FootballFile = JSON.parse(readFileSync(join(__dirname, 'content', 'football_ar_v1.json'), 'utf8'));
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'football' }, select: { payload: true } });
  const have = new Set(existing.map((e) => footballKey(e.payload as Record<string, unknown>)));
  const fresh = items.filter((i) => !have.has(footballKey(i.payload)));
  if (fresh.length === 0) return console.log(`football content up to date (${existing.length} items)`);
  await prisma.contentItem.createMany({
    data: fresh.map((i) => ({
      gameId: 'football',
      category: i.category,
      difficulty: i.difficulty,
      payload: i.payload as object,
      factAsOf: new Date(i.payload.asOf),
      source: 'ai_suggested' as const,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} football items as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

async function main() {
  const approve = process.argv.includes('--approve-for-local-testing');
  await seedSpy(approve);
  await seedLiar(approve);
  await seedWho(approve);
  await seedEmoji(approve);
  await seedStop(approve);
  await seedDraw(approve);
  await seedFootball(approve);
  const all: Row[] = [
    ...QUESTIONS.map(([category, difficulty, prompt, choices, explanation]) => ({
      category, difficulty, prompt, choices, correct: 0, explanation: explanation ?? null, source: 'human' as const,
    })),
    ...loadBank(),
  ];
  const existing = await prisma.contentItem.findMany({ where: { gameId: 'quiz' }, select: { payload: true } });
  const known = new Set(existing.map((e) => String((e.payload as { prompt?: string })?.prompt ?? '')));
  const fresh = all.filter((q) => !known.has(q.prompt) && (known.add(q.prompt), true));
  if (fresh.length === 0) {
    console.log(`quiz content up to date (${existing.length} items)`);
    return;
  }
  await prisma.contentItem.createMany({
    data: fresh.map((q) => ({
      gameId: 'quiz',
      category: q.category,
      difficulty: q.difficulty,
      payload: { prompt: q.prompt, choices: q.choices, correct: q.correct, explanation: q.explanation },
      source: q.source,
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${fresh.length} quiz questions as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

main().finally(() => prisma.$disconnect());
