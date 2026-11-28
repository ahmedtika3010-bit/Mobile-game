/**
 * Shop, missions, daily login, achievements and leaderboards.
 * All amounts and unlocks are decided by the server (see progress/catalog.ts).
 */
import { Router } from 'express';
import { z } from 'zod';
import { HttpError, wrap } from './app';
import {
  ProgressError,
  achievementsView,
  buyItem,
  claimAchievement,
  claimLogin,
  claimMission,
  equip,
  leaderboard,
  missionsView,
  shopView,
} from '../progress/service';
import { ALL_GAMES } from '../progress/catalog';

/** Turns service refusals into HTTP errors the app understands. */
async function run<T>(f: () => Promise<T>): Promise<T> {
  try {
    return await f();
  } catch (e) {
    if (e instanceof ProgressError) throw new HttpError(e.status, e.code);
    throw e;
  }
}

const lbSchema = z.object({
  game: z.enum(['all', ...ALL_GAMES] as [string, ...string[]]).default('all'),
  period: z.enum(['week', 'month', 'all']).default('week'),
  scope: z.enum(['global', 'friends']).default('global'),
  metric: z.enum(['points', 'rating']).default('points'),
});

export function progressRouter() {
  const r = Router();

  r.get('/shop', wrap(async (req, res) => res.json(await run(() => shopView(req.userId!)))));
  r.post('/shop/buy', wrap(async (req, res) => {
    const { itemId } = z.object({ itemId: z.string().max(64) }).parse(req.body);
    res.json(await run(() => buyItem(req.userId!, itemId)));
  }));
  r.post('/shop/equip', wrap(async (req, res) => {
    const { kind, itemId } = z.object({ kind: z.enum(['frame', 'title', 'theme', 'effect']), itemId: z.string().max(64) }).parse(req.body);
    res.json(await run(() => equip(req.userId!, kind, itemId)));
  }));

  r.get('/missions', wrap(async (req, res) => res.json(await run(() => missionsView(req.userId!)))));
  r.post('/missions/claim', wrap(async (req, res) => {
    const { id } = z.object({ id: z.string().max(64) }).parse(req.body);
    res.json({ reward: await run(() => claimMission(req.userId!, id)) });
  }));
  r.post('/login/claim', wrap(async (req, res) => res.json(await run(() => claimLogin(req.userId!)))));

  r.get('/achievements', wrap(async (req, res) => res.json({ achievements: await run(() => achievementsView(req.userId!)) })));
  r.post('/achievements/claim', wrap(async (req, res) => {
    const { id } = z.object({ id: z.string().max(64) }).parse(req.body);
    res.json({ reward: await run(() => claimAchievement(req.userId!, id)) });
  }));

  r.get('/leaderboards', wrap(async (req, res) => {
    const q = lbSchema.parse(req.query);
    res.json(await run(() => leaderboard(req.userId!, { gameId: q.game as never, period: q.period, scope: q.scope, metric: q.metric })));
  }));

  /** Small counts for the home screen badges. */
  r.get('/summary', wrap(async (req, res) => {
    const [m, a] = await Promise.all([run(() => missionsView(req.userId!)), run(() => achievementsView(req.userId!))]);
    const ready = (x: { progress: number; target: number; claimed: boolean }) => !x.claimed && x.progress >= x.target;
    res.json({
      missionsReady: [...m.daily, ...m.weekly].filter(ready).length + (m.login.claimedToday ? 0 : 1),
      achievementsReady: a.filter(ready).length,
      loginReady: !m.login.claimedToday,
    });
  }));

  return r;
}
