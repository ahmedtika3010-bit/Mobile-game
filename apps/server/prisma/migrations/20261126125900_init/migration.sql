-- CreateEnum
CREATE TYPE "AgeBand" AS ENUM ('under_13', 'unknown', 'teen_13_15', 'teen_16_17', 'adult');

-- CreateEnum
CREATE TYPE "AccountStatus" AS ENUM ('active', 'restricted', 'suspended', 'deleted');

-- CreateEnum
CREATE TYPE "AuthProvider" AS ENUM ('google', 'apple', 'dev');

-- CreateEnum
CREATE TYPE "ContentStatus" AS ENUM ('draft', 'in_review', 'approved', 'rejected', 'retired');

-- CreateEnum
CREATE TYPE "ContentSource" AS ENUM ('human', 'import_csv', 'ai_suggested');

-- CreateEnum
CREATE TYPE "MatchState" AS ENUM ('in_progress', 'completed', 'aborted', 'provisional');

-- CreateEnum
CREATE TYPE "Currency" AS ENUM ('coins', 'gems', 'xp');

-- CreateEnum
CREATE TYPE "ReportSeverity" AS ENUM ('critical', 'high', 'medium', 'low');

-- CreateEnum
CREATE TYPE "ReportStatus" AS ENUM ('open', 'in_review', 'actioned', 'dismissed');

-- CreateEnum
CREATE TYPE "SanctionKind" AS ENUM ('warning', 'comm_restriction', 'ranked_ban', 'suspension');

-- CreateEnum
CREATE TYPE "AdminRoleKind" AS ENUM ('owner', 'moderator', 'content_editor');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "displayName" TEXT,
    "avatarId" TEXT NOT NULL DEFAULT 'chibi_base_1',
    "dateOfBirth" DATE,
    "ageBand" "AgeBand" NOT NULL DEFAULT 'unknown',
    "status" "AccountStatus" NOT NULL DEFAULT 'active',
    "onboarded" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuthIdentity" (
    "id" TEXT NOT NULL,
    "provider" "AuthProvider" NOT NULL,
    "subject" TEXT NOT NULL,
    "email" TEXT,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuthIdentity_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefreshToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefreshToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ContentItem" (
    "id" TEXT NOT NULL,
    "gameId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "language" TEXT NOT NULL DEFAULT 'ar',
    "locale" TEXT,
    "difficulty" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "acceptedAnswers" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "status" "ContentStatus" NOT NULL DEFAULT 'draft',
    "source" "ContentSource" NOT NULL DEFAULT 'human',
    "factAsOf" DATE,
    "expiresAt" TIMESTAMP(3),
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "importBatchId" TEXT,

    CONSTRAINT "ContentItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ContentReview" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "reviewerId" TEXT NOT NULL,
    "decision" "ContentStatus" NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ContentReview_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ImportBatch" (
    "id" TEXT NOT NULL,
    "uploadedBy" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "rowCount" INTEGER NOT NULL,
    "errorCount" INTEGER NOT NULL,
    "errors" JSONB NOT NULL DEFAULT '[]',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ImportBatch_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Match" (
    "id" TEXT NOT NULL,
    "roomId" TEXT NOT NULL,
    "gameId" TEXT NOT NULL,
    "mode" TEXT NOT NULL,
    "commMode" TEXT NOT NULL,
    "config" JSONB NOT NULL,
    "seed" TEXT NOT NULL,
    "state" "MatchState" NOT NULL DEFAULT 'in_progress',
    "integrityOk" BOOLEAN NOT NULL DEFAULT true,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),

    CONSTRAINT "Match_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MatchPlayer" (
    "matchId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "team" INTEGER,
    "score" INTEGER NOT NULL DEFAULT 0,
    "place" INTEGER,
    "performance" DOUBLE PRECISION,
    "leftEarly" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "MatchPlayer_pkey" PRIMARY KEY ("matchId","userId")
);

-- CreateTable
CREATE TABLE "MatchEvent" (
    "id" BIGSERIAL NOT NULL,
    "matchId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "userId" TEXT,
    "kind" TEXT NOT NULL,
    "data" JSONB NOT NULL,

    CONSTRAINT "MatchEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SkillRating" (
    "userId" TEXT NOT NULL,
    "gameId" TEXT NOT NULL,
    "mu" DOUBLE PRECISION NOT NULL,
    "sigma" DOUBLE PRECISION NOT NULL,
    "matches" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SkillRating_pkey" PRIMARY KEY ("userId","gameId")
);

-- CreateTable
CREATE TABLE "RatingChange" (
    "id" TEXT NOT NULL,
    "matchId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "gameId" TEXT NOT NULL,
    "muBefore" DOUBLE PRECISION NOT NULL,
    "muAfter" DOUBLE PRECISION NOT NULL,
    "sigmaBefore" DOUBLE PRECISION NOT NULL,
    "sigmaAfter" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RatingChange_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Progression" (
    "userId" TEXT NOT NULL,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "level" INTEGER NOT NULL DEFAULT 1,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Progression_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "LedgerEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "currency" "Currency" NOT NULL,
    "amount" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "refId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Report" (
    "id" TEXT NOT NULL,
    "reporterId" TEXT NOT NULL,
    "reportedId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "severity" "ReportSeverity" NOT NULL,
    "status" "ReportStatus" NOT NULL DEFAULT 'open',
    "matchId" TEXT,
    "roomId" TEXT,
    "note" TEXT,
    "evidence" JSONB,
    "evidenceExpiresAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),
    "resolvedBy" TEXT,

    CONSTRAINT "Report_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Block" (
    "blockerId" TEXT NOT NULL,
    "blockedId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Block_pkey" PRIMARY KEY ("blockerId","blockedId")
);

-- CreateTable
CREATE TABLE "Sanction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" "SanctionKind" NOT NULL,
    "reason" TEXT NOT NULL,
    "reportId" TEXT,
    "issuedBy" TEXT NOT NULL,
    "startsAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endsAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "appeal" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Sanction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminRole" (
    "userId" TEXT NOT NULL,
    "role" "AdminRoleKind" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminRole_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" BIGSERIAL NOT NULL,
    "actorId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT,
    "data" JSONB,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AuthIdentity_provider_subject_key" ON "AuthIdentity"("provider", "subject");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshToken_tokenHash_key" ON "RefreshToken"("tokenHash");

-- CreateIndex
CREATE INDEX "ContentItem_gameId_status_language_difficulty_idx" ON "ContentItem"("gameId", "status", "language", "difficulty");

-- CreateIndex
CREATE INDEX "MatchEvent_matchId_idx" ON "MatchEvent"("matchId");

-- CreateIndex
CREATE UNIQUE INDEX "RatingChange_matchId_userId_key" ON "RatingChange"("matchId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "LedgerEntry_idempotencyKey_key" ON "LedgerEntry"("idempotencyKey");

-- CreateIndex
CREATE INDEX "LedgerEntry_userId_currency_idx" ON "LedgerEntry"("userId", "currency");

-- CreateIndex
CREATE INDEX "Report_status_severity_idx" ON "Report"("status", "severity");

-- CreateIndex
CREATE INDEX "AuditLog_targetType_targetId_idx" ON "AuditLog"("targetType", "targetId");

-- AddForeignKey
ALTER TABLE "AuthIdentity" ADD CONSTRAINT "AuthIdentity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ContentItem" ADD CONSTRAINT "ContentItem_importBatchId_fkey" FOREIGN KEY ("importBatchId") REFERENCES "ImportBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ContentReview" ADD CONSTRAINT "ContentReview_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "ContentItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MatchPlayer" ADD CONSTRAINT "MatchPlayer_matchId_fkey" FOREIGN KEY ("matchId") REFERENCES "Match"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MatchPlayer" ADD CONSTRAINT "MatchPlayer_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MatchEvent" ADD CONSTRAINT "MatchEvent_matchId_fkey" FOREIGN KEY ("matchId") REFERENCES "Match"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SkillRating" ADD CONSTRAINT "SkillRating_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Progression" ADD CONSTRAINT "Progression_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LedgerEntry" ADD CONSTRAINT "LedgerEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Report" ADD CONSTRAINT "Report_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Report" ADD CONSTRAINT "Report_reportedId_fkey" FOREIGN KEY ("reportedId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Block" ADD CONSTRAINT "Block_blockerId_fkey" FOREIGN KEY ("blockerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Block" ADD CONSTRAINT "Block_blockedId_fkey" FOREIGN KEY ("blockedId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sanction" ADD CONSTRAINT "Sanction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdminRole" ADD CONSTRAINT "AdminRole_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
