/**
 * Arabic-aware text normalization used for answer matching.
 *
 * Rule: normalization only removes differences that Arabic readers treat as
 * spelling noise (diacritics, tatweel, hamza seat on alef, alef maqsura,
 * taa marbuta, Arabic-Indic digits, punctuation, spacing). It never invents
 * a correct answer: matching still requires an approved answer or an approved
 * variant stored in the content database.
 */

const TASHKEEL = /[ؐ-ًؚ-ٰٟۖ-ۭ]/g;
const TATWEEL = /ـ/g;
const PUNCT = /[،؛؟٪-٭.,;:!?'"()\[\]{}\-_/\\|@#$%^&*+=<>~`«»“”‘’]/g;

const ARABIC_INDIC = '٠١٢٣٤٥٦٧٨٩';
const PERSIAN_DIGITS = '۰۱۲۳۴۵۶۷۸۹';

export function normalizeDigits(s: string): string {
  let out = '';
  for (const ch of s) {
    const a = ARABIC_INDIC.indexOf(ch);
    const p = PERSIAN_DIGITS.indexOf(ch);
    out += a >= 0 ? String(a) : p >= 0 ? String(p) : ch;
  }
  return out;
}

export function normalizeArabic(input: string): string {
  return normalizeDigits(input)
    .normalize('NFKC')
    .replace(TASHKEEL, '')
    .replace(TATWEEL, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/ؤ/g, 'و')
    .replace(/ئ/g, 'ي')
    .replace(PUNCT, ' ')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** Strips a leading definite article from each word ("ال", "وال"). Used only
 * where an item explicitly allows article-insensitive matching. */
export function stripDefiniteArticle(normalized: string): string {
  return normalized
    .split(' ')
    .map((w) => (w.length > 3 && w.startsWith('ال') ? w.slice(2) : w))
    .join(' ');
}

export interface AnswerMatchOptions {
  ignoreDefiniteArticle?: boolean;
}

/**
 * Returns the index of the approved answer that matches the input, or -1.
 * Only exact matches after normalization count; no fuzzy guessing.
 */
export function matchApprovedAnswer(
  input: string,
  approved: readonly string[],
  opts: AnswerMatchOptions = {},
): number {
  const norm = (s: string) => {
    const n = normalizeArabic(s);
    return opts.ignoreDefiniteArticle ? stripDefiniteArticle(n) : n;
  };
  const target = norm(input);
  if (!target) return -1;
  return approved.findIndex((a) => norm(a) === target);
}
