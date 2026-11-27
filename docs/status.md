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
| Who Is the Liar? (مين الكداب؟) | Third game. Each round one player secretly gets a similar but different question (they are not told); everyone picks an answer from the pair's approved options; then the main question and all answers are shown, players mark suspects, discuss with approved phrases and vote anonymously. Catching the liar gives each correct voter 100; an escaped liar gets 150. The liar role rotates fairly; hosts pick difficulty (how similar the two questions are) and rounds. The odd question and the liar never reach anyone before the round ends. Unit + end-to-end tests |
| Who Among Us? (مين فينا؟) | Fourth game. Approved "who among us would..." questions (13+); everyone votes anonymously for another player or skips. The reveal shows the most-voted player (up to two on a tie), hides the result when fewer than 3 voted, shows counts only from 5 votes, and caps how often one player can be shown (anti-targeting). No winner, loser or rating; friendly titles at the end and small flat participation rewards. Unit + end-to-end tests |
| Guess with Emoji (خمّن بالإيموجي) | Fifth game. Emoji puzzles in 6 categories (movies and TV, football, food, countries and cities, sayings, games and characters) at 3 difficulties. Same fair timing and scoring as the quiz (common reveal time, 100 + up to 50 speed points in whole seconds). Public, practice and ranked use multiple choice with a standard profile; private rooms may switch to typed answers, matched only against the approved answer and its approved variants after Arabic normalization (article-insensitive), 3 wrong guesses per puzzle, guesses never sent to other players, answer shape shown at half time. Puzzles must avoid emoji newer than Emoji 11 so older Android phones draw them (checked by tests and the admin schema). Unit + end-to-end tests |
| Stop / Atobees Complete (أتوبيس كومبليت) | Sixth game. Each round draws a letter the dictionary covers in every category (21 letters today, none twice per match); six cells: boy's name, girl's name, animal, plant, object, country or city. Same timer for everyone, sheets editable until it ends (autosaved), early end only when every connected player is done. Dictionary check after Arabic normalization (hamza, taa marbuta, alef maqsura, diacritics, leading "ال", spaces): 10 unique, 5 shared, 0 wrong letter, empty or unknown. Unknown words are shown only to their author, who can appeal; appeals are saved as `in_review` dictionary items and, once approved, count in future matches. Scores of a finished match never change, so the game is not ranked yet. Practice bots use real dictionary words. Unit + end-to-end tests |
| Memory Challenges (تحديات الذاكرة) | Seventh game. Three modes, mixed by default: memory cards (find where each target emoji was), sequence (repeat the order of lit color pads) and spot the change (tap the one card that changed). Every round is generated from the match seed with no content to review; the board is shown between a common `showAt` and `hideAt` server time so every phone gets the same exposure, answers open together and close at one deadline. Partial credit (targets found or correct prefix of the sequence) out of 100, plus a small speed bonus in whole seconds only for a fully correct answer. Private rooms may pick mode, difficulty (6, 9 or 12 cards; sequences of 4, 6 or 8) and 3 to 9 rounds. Not ranked yet: the board reaches the phone, so a modified client could keep it on screen. Team play is not built. Unit + end-to-end tests |
| Practice mode | Solo match against three labelled bots (🤖, names start with "بوت") with varied skill and human-like timing. No XP, coins, rating or match records. Integration test covers it |
| Admin API | Report queue and resolution with sanctions, content create, CSV import as drafts, human approval, audit log, basic stats; roles ready for moderators |

## Done (app)

| Area | Notes |
| --- | --- |
| Dart client | HTTP API with token refresh, Colyseus 0.16 protocol, MessagePack, clock sync, automatic reconnect within 90 s. Tested live against the server |
| Flutter app | Arabic RTL, home with the game list, sign-in, onboarding (name, avatar, date of birth), quiz hub (quick, ranked, private create, join by code), lobby, countdown, question, reveal, results with rewards, approved phrases, Safe Mode badge, report and block, reconnecting banner, safety center |
| Stop screens | Big letter badge, six cells with a wrong-letter hint, autosave and a "done" button; round review with every player's words and points (unknown words hidden from others), appeal button; results with ranking and the letters played |
| Emoji screens | Big emoji puzzle card on the quiz screens; typed-answer box with tries left, your crossed-out wrong guesses, the answer shape after half time and the answer on reveal; private-room pickers for difficulty and answer mode |
| Memory screens | Card grid that turns face down on the server's hide time, target row ("where was X?"), spot-the-change grid, four color pads that light in turn with progress dots, clear and confirm buttons, reveal with green and red borders and everyone's answers, results with ranking |
| Characters | 10 grown-up personas (young men and women, two in hijab, an older man, a Gulf-style ghutra) with 4 expressions each, generated from `design/personas`; shown first in the avatar picker, the original four kept after them |
| Spy screens | Role reveal (with hide button), ask/answer turns, history of questions, discussion with suspicion badges, secret vote, last-chance guess, results with the word, the spies and vote totals |
| Feel | Sound effects (tap, countdown, question, pick, correct/wrong, join, win) with haptics and a mute toggle in the room and profile; after each question, the avatars of who picked each answer; a personal result card that can be shared as an image |
| Verified | Widget tests, and a browser-driven web build playing a full private match against a bot through to the results screen |

## Partial

- Google and Apple sign-in: code is in place, but needs your OAuth client ids and Apple capability (see `docs/mobile.md`). Apple is iOS only.
- Android build: a debug APK was built on the owner's PC and tested on a phone over the local network. iOS: not built (needs a Mac).
- Closed test online (`docs/deploy-render.md`): `render.yaml` (Render free web service + Neon free Postgres) and invite-code sign-in (`/auth/tester`, app flag `TESTER_SIGN_IN`). Tested locally in production mode; the hosted service is not created yet. Free tier sleeps when idle (first open about a minute).
- Question bank: 273 quiz questions (20 hand-written + 253 in `apps/server/prisma/content/quiz_ar_v1.csv`, 6 categories). The 253 were drafted with AI help, so they are inserted as `ai_suggested` and `in_review`: someone must fact-check and approve them in the admin before release. `--approve-for-local-testing` approves them on a dev machine only.
- Share card: works on Android/iOS through the system share sheet; on desktop browsers without Web Share, it shows a "could not share" message.
- Who Among Us content: 80 questions in 4 categories in `apps/server/prisma/content/who_ar_v1.json`, AI-drafted, seeded as `in_review` until approved.
- Liar content: 60 question pairs (20 easy, 20 medium, 20 hard) in `apps/server/prisma/content/liar_ar_v1.json`, AI-drafted, seeded as `in_review` until approved. No ranked queue and no practice bots yet.
- Spy content: 6 category packs (places, food, jobs, animals, household objects, sports; 18 to 20 words and 16 questions each) in `apps/server/prisma/content/spy_ar_v1.json`, AI-assisted, so seeded as `in_review` until approved. Spy has no ranked queue and no practice bots yet (ranked needs playtesting of the standardized rules first).
- Stop dictionary: about 970 words (boys 204, girls 157, animals 127, plants 107, objects 125, countries and cities 249) in `apps/server/prisma/content/stop_ar_v1.json`, AI-drafted, seeded as `in_review` until approved. Coverage decides which letters can come up; rare letters (ث، ذ، ض، ط، ظ، غ) need more words first. Regional variants are separate words (e.g. طماطم and بندورة both count). Peer voting on unknown words during a match is not built (it would show unreviewed text to other players).
- Emoji content: 91 puzzles (31 easy, 33 medium, 27 hard) in `apps/server/prisma/content/emoji_ar_v1.json`, AI-drafted with spelling variants, seeded as `in_review` until approved. The emoji check covers the main ranges of newer emoji but is not a full Unicode version table.
- Characters: four designer characters (Kairo, Sira, Forest spirit, Rithia), cut out of the character sheets in `design/characters` as still images. Expressions and animation (Rive) are still to come; ideally the designer delivers separate transparent PNGs or Rive files per pose.

## Pending (not started or not usable yet)

- Final Chibi art and animation (needs an artist); final sound design (current sounds are simple synthesized placeholders)
- Web admin dashboard UI (API exists)
- The other three games (football, draw and guess, acting), Game Night, friends, presence, direct messages, notifications
- Missions, achievements, leaderboards, cosmetics shop, Gems purchases (store billing), rewarded ads
- Voice (LiveKit) and free text chat in Normal Mode: not implemented, so only approved phrases exist today
- Appeals flow, anti-cheat analysis, parental controls, events
- Multi-server deployment (Redis presence/driver), monitoring, backups
- Legal and store compliance review; human moderation coverage plan

## Needs playtesting (configurable defaults, not final decisions)

Scoring (100 + up to 50 speed), countdowns, reward amounts, daily coin cap (300), level curve, provisional period (10 matches), report retention (90 days).
