import { OAuth2Client } from 'google-auth-library';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { config } from '../config';

export interface VerifiedIdentity {
  provider: 'google' | 'apple';
  subject: string;
  email: string | null;
}

const google = new OAuth2Client();

export async function verifyGoogleIdToken(idToken: string): Promise<VerifiedIdentity> {
  if (config.googleClientIds.length === 0) throw new Error('google_not_configured');
  const ticket = await google.verifyIdToken({ idToken, audience: config.googleClientIds });
  const p = ticket.getPayload();
  if (!p?.sub) throw new Error('invalid_google_token');
  return { provider: 'google', subject: p.sub, email: p.email_verified ? p.email ?? null : null };
}

const appleJwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export async function verifyAppleIdToken(idToken: string): Promise<VerifiedIdentity> {
  if (config.appleBundleIds.length === 0) throw new Error('apple_not_configured');
  const { payload } = await jwtVerify(idToken, appleJwks, {
    issuer: 'https://appleid.apple.com',
    audience: config.appleBundleIds,
  });
  if (!payload.sub) throw new Error('invalid_apple_token');
  return { provider: 'apple', subject: payload.sub, email: (payload.email as string | undefined) ?? null };
}
