import { describe, expect, it } from 'vitest';
import { computeAgeBand, roomCommMode } from '../src/age';

const now = new Date('2026-11-26T00:00:00Z');

describe('computeAgeBand', () => {
  it('handles birthdays exactly', () => {
    expect(computeAgeBand('2008-11-26', now)).toBe('adult');
    expect(computeAgeBand('2008-11-27', now)).toBe('teen_16_17');
    expect(computeAgeBand('2013-11-26', now)).toBe('teen_13_15');
    expect(computeAgeBand('2013-11-27', now)).toBe('under_13');
  });
  it('treats missing or invalid dates as unknown', () => {
    expect(computeAgeBand(null, now)).toBe('unknown');
    expect(computeAgeBand('not-a-date', now)).toBe('unknown');
  });
});

describe('roomCommMode', () => {
  it('is normal only when everyone is an adult', () => {
    expect(roomCommMode(['adult', 'adult'])).toBe('normal');
    expect(roomCommMode(['adult', 'teen_16_17'])).toBe('safe');
    expect(roomCommMode(['adult', 'unknown'])).toBe('safe');
    expect(roomCommMode([])).toBe('safe');
  });
});
