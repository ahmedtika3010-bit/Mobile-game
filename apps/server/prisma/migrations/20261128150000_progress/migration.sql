-- AlterTable
ALTER TABLE "Match" ADD COLUMN     "night" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "loadout" JSONB NOT NULL DEFAULT '{}';

-- CreateTable
CREATE TABLE "OwnedCosmetic" (
    "userId" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OwnedCosmetic_pkey" PRIMARY KEY ("userId","itemId")
);

-- CreateTable
CREATE TABLE "RewardClaim" (
    "userId" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RewardClaim_pkey" PRIMARY KEY ("userId","key")
);

-- AddForeignKey
ALTER TABLE "OwnedCosmetic" ADD CONSTRAINT "OwnedCosmetic_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RewardClaim" ADD CONSTRAINT "RewardClaim_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

