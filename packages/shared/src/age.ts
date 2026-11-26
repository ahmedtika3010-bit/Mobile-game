/** Age bands. Unknown or unverified age is always treated like a minor. */
export type AgeBand = 'under_13' | 'unknown' | 'teen_13_15' | 'teen_16_17' | 'adult';

export const MIN_AGE = 13;

export function ageInYears(dobIso: string, now: Date): number {
  const [y, m, d] = dobIso.split('-').map(Number) as [number, number, number];
  let age = now.getUTCFullYear() - y;
  const beforeBirthday =
    now.getUTCMonth() + 1 < m || (now.getUTCMonth() + 1 === m && now.getUTCDate() < d);
  if (beforeBirthday) age -= 1;
  return age;
}

export function computeAgeBand(dobIso: string | null | undefined, now: Date): AgeBand {
  if (!dobIso || !/^\d{4}-\d{2}-\d{2}$/.test(dobIso)) return 'unknown';
  const age = ageInYears(dobIso, now);
  if (age < 0 || age > 120) return 'unknown';
  if (age < MIN_AGE) return 'under_13';
  if (age <= 15) return 'teen_13_15';
  if (age <= 17) return 'teen_16_17';
  return 'adult';
}

/** True when the band must receive minor protections (includes unknown). */
export function needsMinorProtections(band: AgeBand): boolean {
  return band !== 'adult';
}

export type CommMode = 'normal' | 'safe';

/**
 * A room is in Normal Mode only if every participant is a verified adult.
 * Any minor or unknown age switches the whole room to Safe Mode. Room hosts
 * cannot override this.
 */
export function roomCommMode(bands: readonly AgeBand[]): CommMode {
  return bands.length > 0 && bands.every((b) => b === 'adult') ? 'normal' : 'safe';
}

/** Coarse matchmaking bucket: adults are never auto-matched with minors in public queues. */
export function matchmakingAgeBucket(band: AgeBand): 'adult' | 'minor' {
  return band === 'adult' ? 'adult' : 'minor';
}
