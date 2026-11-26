import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

// Minimal .env loader (avoids an extra dependency). Real env vars win.
const envPath = join(__dirname, '..', '.env');
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]!] === undefined) process.env[m[1]!] = m[2];
  }
}

const list = (v: string | undefined) => (v ?? '').split(',').map((s) => s.trim()).filter(Boolean);

export const config = {
  /** Working title only; the brand name is not final. */
  appName: process.env.APP_NAME || 'Sahra',
  port: Number(process.env.PORT || 2567),
  jwtSecret: process.env.JWT_SECRET || '',
  googleClientIds: list(process.env.GOOGLE_CLIENT_IDS),
  appleBundleIds: list(process.env.APPLE_BUNDLE_IDS),
  devAuth: process.env.DEV_AUTH === '1' && process.env.NODE_ENV !== 'production',
  accessTokenTtlSec: 15 * 60,
  refreshTokenTtlDays: 30,
  reconnectSeconds: 90,
  economy: {
    dailyMatchCoinCap: 300,
    privateRoomMinPlayersForCoins: 3,
  },
  rating: { provisionalMatches: 10 },
  reportEvidenceRetentionDays: 90,
};

export function assertConfig() {
  if (config.jwtSecret.length < 32) throw new Error('JWT_SECRET must be set (at least 32 characters)');
}
