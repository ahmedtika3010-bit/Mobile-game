import { describe, expect, it } from 'vitest';
import { matchApprovedAnswer, normalizeArabic } from '../src/arabic';

describe('normalizeArabic', () => {
  it('removes diacritics and tatweel and unifies alef forms', () => {
    expect(normalizeArabic('أَحْمَــد')).toBe('احمد');
    expect(normalizeArabic('إسكندرية')).toBe(normalizeArabic('اسكندريه'));
    expect(normalizeArabic('مصطفى')).toBe('مصطفي');
  });
  it('converts Arabic-Indic digits', () => {
    expect(normalizeArabic('١٩٥٢')).toBe('1952');
  });
  it('collapses spaces and punctuation', () => {
    expect(normalizeArabic('  القاهرة،   مصر! ')).toBe('القاهره مصر');
  });
});

describe('matchApprovedAnswer', () => {
  const approved = ['القاهرة', 'Cairo'];
  it('matches spelling variants of approved answers only', () => {
    expect(matchApprovedAnswer('القاهره', approved)).toBe(0);
    expect(matchApprovedAnswer('cairo', approved)).toBe(1);
    expect(matchApprovedAnswer('الجيزة', approved)).toBe(-1);
    expect(matchApprovedAnswer('', approved)).toBe(-1);
  });
  it('ignores the definite article only when asked', () => {
    expect(matchApprovedAnswer('قاهرة', approved)).toBe(-1);
    expect(matchApprovedAnswer('قاهرة', approved, { ignoreDefiniteArticle: true })).toBe(0);
  });
});
