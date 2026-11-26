#!/usr/bin/env sh
# Start command for the hosted closed test (see docs/deploy-render.md).
set -e
cd "$(dirname "$0")/.."
npx prisma migrate deploy
if [ "$SEED_APPROVED_CONTENT" = "1" ]; then
  # Closed test with friends only: loads the AI-drafted question bank and spy
  # packs as approved. Idempotent (adds only what is missing). Turn this off
  # once the content goes through human review in the admin panel.
  npx tsx prisma/seed.ts --approve-for-local-testing
fi
exec npx tsx src/index.ts
