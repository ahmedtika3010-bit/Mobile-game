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
| Spy (الجاسوس) | Second game. Secret word for everyone except the spy (category only); question turns with approved questions per category and an approved five-step answer scale; public suspicion markers and ready-to-vote discussion; anonymous vote; a caught spy gets one guess; a spy may guess early (right wins, wrong loses). 1 spy, or 2 from 7 players in private rooms. Roles and the word never reach players who must not see them. Unit + end-to-end tests |
| Practice mode | Solo match against three labelled bots (🤖, names start with "بوت") with varied skill and human-like timing. No XP, coins, rating or match records. Integration test covers it |
| Admin API | Report queue and resolution with sanctions, content create, CSV import as drafts, human approval, audit log, basic stats; roles ready for moderators |

## Done (app)

| Area | Notes |
| --- | --- |
| Dart client | HTTP API with token refresh, Colyseus 0.16 protocol, MessagePack, clock sync, automatic reconnect within 90 s. Tested live against the server |
| Flutter app | Arabic RTL, home with the game list, sign-in, onboarding (name, avatar, date of birth), quiz hub (quick, ranked, private create, join by code), lobby, countdown, question, reveal, results with rewards, approved phrases, Safe Mode badge, report and block, reconnecting banner, safety center |
| Spy screens | Role reveal (with hide button), ask/answer turns, history of questions, discussion with suspicion badges, secret vote, last-chance guess, results with the word, the spies and vote totals |
| Feel | Sound effects (tap, countdown, question, pick, correct/wrong, join, win) with haptics and a mute toggle in the room and profile; after each question, the avatars of who picked each answer; a personal result card that can be shared as an image |
| Verified | Widget tests, and a browser-driven web build playing a full private match against a bot through to the results screen |

## Partial

- Google and Apple sign-in: code is in place, but needs your OAuth client ids and Apple capability (see `docs/mobile.md`). Apple is iOS only.
- Android build: a debug APK was built on the owner's PC and tested on a phone over the local network. iOS: not built (needs a Mac).
- Closed test online (`docs/deploy-render.md`): `render.yaml` (Render free web service + Neon free Postgres) and invite-code sign-in (`/auth/tester`, app flag `TESTER_SIGN_IN`). Tested locally in production mode; the hosted service is not created yet. Free tier sleeps when idle (first open about a minute).
- Question bank: 273 quiz questions (20 hand-written + 253 in `apps/server/prisma/content/quiz_ar_v1.csv`, 6 categories). The 253 were drafted with AI help, so they are inserted as `ai_suggested` and `in_review`: someone must fact-check and approve them in the admin before release. `--approve-for-local-testing` approves them on a dev machine only.
- Share card: works on Android/iOS through the system share sheet; on desktop browsers without Web Share, it shows a "could not share" message.
- Spy content: 6 category packs (places, food, jobs, animals, household objects, sports; 18 to 20 words and 16 questions each) in `apps/server/prisma/content/spy_ar_v1.json`, AI-assisted, so seeded as `in_review` until approved. Spy has no ranked queue and no practice bots yet (ranked needs playtesting of the standardized rules first).
- Characters: four designer characters (Kairo, Sira, Forest spirit, Rithia), cut out of the character sheets in `design/characters` as still images. Expressions and animation (Rive) are still to come; ideally the designer delivers separate transparent PNGs or Rive files per pose.

## Pending (not started or not usable yet)

- Final Chibi art and animation (needs an artist); final sound design (current sounds are simple synthesized placeholders)
- Web admin dashboard UI (API exists)
- The other eight games, Game Night, friends, presence, direct messages, notifications
- Missions, achievements, leaderboards, cosmetics shop, Gems purchases (store billing), rewarded ads
- Voice (LiveKit) and free text chat in Normal Mode: not implemented, so only approved phrases exist today
- Appeals flow, anti-cheat analysis, parental controls, events
- Multi-server deployment (Redis presence/driver), monitoring, backups
- Legal and store compliance review; human moderation coverage plan

## Needs playtesting (configurable defaults, not final decisions)

Scoring (100 + up to 50 speed), countdowns, reward amounts, daily coin cap (300), level curve, provisional period (10 matches), report retention (90 days).
