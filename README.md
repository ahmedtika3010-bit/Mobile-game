# Sahra (working title) — multiplayer party games platform

Arabic-first (RTL) social party games for Android and iOS. "Sahra" is a
working title only; the app name is configured in one place (`APP_NAME`).

See [`docs/status.md`](docs/status.md) for exactly what works today.

## Layout

| Path | What |
| --- | --- |
| `packages/shared` | Types and rules shared by server and clients: wire protocol, Arabic answer normalization, age bands and Safe Mode policy |
| `apps/server` | Authoritative game server (Colyseus over WebSocket) + HTTP API (Express), PostgreSQL via Prisma |
| `apps/server/prisma` | Database schema, migrations, sample seed |
| `packages/sahra_client` | Pure-Dart client for the API and game server (used by the app, testable without Flutter) |
| `apps/mobile` | Flutter app for Android and iOS, see [`docs/mobile.md`](docs/mobile.md) |

## Run locally

Requirements: Node 20+, PostgreSQL 16 (or `docker compose up -d`). Flutter 3.47 (the version tested) for the app.

```bash
npm install
cp apps/server/.env.example apps/server/.env   # set JWT_SECRET; DEV_AUTH=1 for local sign-in
cd apps/server
npx prisma migrate deploy
npm run db:seed -- --approve-for-local-testing  # sample questions (unreviewed!)
npm run dev                                       # http://localhost:2567
```

Tests (need the database from `.env`):

```bash
npm test          # unit + end-to-end tests with real WebSocket clients
npm run typecheck
```

Make yourself the admin owner after signing in once:

```bash
cd apps/server && npx tsx src/scripts/grant-admin.ts <your-user-id> owner
```

## Key rules enforced by the server

- The server decides questions, timers, answers, scores, rewards and ratings; clients only send actions.
- Each player receives a view built for them; hidden answers are never sent early.
- Rooms with any minor or unknown-age player run in Safe Mode, which never switches back automatically.
- Adults and minors are never matched together in public queues.
- Rewards are ledger entries with unique idempotency keys: retries cannot pay twice.
- Content (including imports and AI suggestions) is playable only after human approval.
