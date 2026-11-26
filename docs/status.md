# Implementation status

Updated: 2026-11-26. "Done" means connected end to end and covered by tests.

## Done (server)

| Area | Notes |
| --- | --- |
| Accounts | Google and Apple ID-token verification, JWT access tokens, rotating refresh tokens. Dev sign-in for local/tests only (`DEV_AUTH=1`, off in production) |
| Onboarding | Display name, avatar id, date of birth (set once, never returned by the API), age bands, under-13 blocked, unknown age treated as minor |
| Matchmaking | Server-minted seat tickets; public queues split by game, mode and age group; room re-checks everything; blocked players are not seated together |
| Private rooms | 6-character codes, host settings within limits, host start, host handover |
| Game engine | One room type for all games; per-player views; seeded randomness stored per match; 90 s reconnection; late joiners wait for the next match |
| General Knowledge Quiz | Server-authoritative, synchronized reveal time, bucketed speed bonus with capped latency compensation, standardized ranked config |
| Safe Mode | Computed from all members, sticky for the room, approved quick-chat phrases only |
| Persistence | Matches, players, action log, results |
| Economy | Double-entry style ledger with idempotency keys, XP and levels, daily coin cap, reduced private-room rewards |
| Ratings | OpenSkill per game, provisional period, ranked only, departures count as a loss, invalid matches not rated |
| Safety | Reports with severity, automatic restriction on critical reports, auto-block on report, blocking API, evidence retention date |
| Admin API | Report queue and resolution with sanctions, content create, CSV import as drafts, human approval, audit log, basic stats; roles ready for moderators |

## Pending (not started or not usable yet)

- Flutter mobile app (next step), design system, Chibi avatars (needs an artist)
- Web admin dashboard UI (API exists)
- The other nine games, Game Night, friends, presence, direct messages, notifications
- Missions, achievements, leaderboards, cosmetics shop, Gems purchases (store billing), rewarded ads
- Voice (LiveKit) and free text chat in Normal Mode: not implemented, so only approved phrases exist today
- Appeals flow, anti-cheat analysis, parental controls, shareable cards, events
- Multi-server deployment (Redis presence/driver), monitoring, backups
- Legal and store compliance review; human moderation coverage plan

## Needs playtesting (configurable defaults, not final decisions)

Scoring (100 + up to 50 speed), countdowns, reward amounts, daily coin cap (300), level curve, provisional period (10 matches), report retention (90 days).
