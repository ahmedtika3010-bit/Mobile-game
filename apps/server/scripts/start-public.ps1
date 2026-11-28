# Runs the game server on this PC for friends over the internet, through an
# ngrok static domain (closed test, no hosting account needed).
# Developer sign-in is OFF; friends sign in with the invite code.
#
# Usage, from the repository folder:
#   powershell -ExecutionPolicy Bypass -File apps\server\scripts\start-public.ps1 -Domain your-name.ngrok-free.app
param(
  [Parameter(Mandatory = $true)][string]$Domain,
  [string]$Ngrok = "C:\tools\ngrok\ngrok.exe"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not $env:CLOSED_TEST_CODE) {
  $env:CLOSED_TEST_CODE = Read-Host "Invite code for your friends (6+ characters)"
}
$env:NODE_ENV = "production"
$env:DEV_AUTH = "0"
$env:TRUST_PROXY = "1"

npx prisma migrate deploy
if ($LASTEXITCODE -ne 0) { throw "Database migration failed" }
# Closed test only: AI-drafted content is approved for play (see docs/status.md).
npx tsx prisma/seed.ts --approve-for-local-testing
if ($LASTEXITCODE -ne 0) { throw "Seeding content failed" }

Write-Host "Opening the public tunnel: https://$Domain"
Start-Process -FilePath $Ngrok -ArgumentList "http", "--url=https://$Domain", "2567"
npx tsx src/index.ts
