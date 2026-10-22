<#
.SYNOPSIS
  Runs the whole AutoMind AI stack on this Windows PC with Docker Desktop:
  PostgreSQL + Redis + API (http://localhost:8000) + admin dashboard (http://localhost:3000)
  + ECU simulator (tcp://localhost:35000, always labelled DEMO).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\windows\start-local.ps1          # start / update
  powershell -ExecutionPolicy Bypass -File scripts\windows\start-local.ps1 -Stop    # stop
  powershell -ExecutionPolicy Bypass -File scripts\windows\start-local.ps1 -Reset   # stop and delete local data
#>
param([switch]$Stop, [switch]$Reset)

$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "..\.."))

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker Desktop is not installed: https://www.docker.com/products/docker-desktop/" -ForegroundColor Red
    Write-Host "ثبّت Docker Desktop أولا ثم أعد تشغيل هذا الملف." -ForegroundColor Red
    exit 1
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Start Docker Desktop and wait until it says 'Engine running', then run this again." -ForegroundColor Yellow
    Write-Host "شغّل Docker Desktop وانتظر حتى يجهز ثم أعد المحاولة." -ForegroundColor Yellow
    exit 1
}

if ($Stop)  { docker compose down; exit $LASTEXITCODE }
if ($Reset) { docker compose down -v; Remove-Item .env -ErrorAction SilentlyContinue; Write-Host "Local data deleted."; exit 0 }

function New-RandomBase64([int]$bytes) {
    $buf = New-Object byte[] $bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buf); $rng.Dispose()
    return [Convert]::ToBase64String($buf)
}

if (-not (Test-Path .env)) {
    Write-Host "Creating .env with new random local secrets..."
    $pg = (New-RandomBase64 24) -replace '[+/=]', ''
    @(
        "POSTGRES_PASSWORD=$pg",
        "AUTOMIND_JWT_SECRET=$(New-RandomBase64 48)",
        "AUTOMIND_DATA_ENCRYPTION_KEY=$(New-RandomBase64 32)",
        "AUTOMIND_BLIND_INDEX_KEY=$(New-RandomBase64 32)",
        "ANTHROPIC_API_KEY=",
        "NEXT_PUBLIC_API_BASE_URL=http://localhost:8000/api/v1"
    ) | Set-Content -Path .env -Encoding ascii
    Write-Host "Keep .env private; it is ignored by git." -ForegroundColor DarkGray
}

Write-Host "Building and starting containers (first run takes a few minutes)..."
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Write-Host "docker compose failed" -ForegroundColor Red; exit 1 }

Write-Host -NoNewline "Waiting for the API"
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/health/ready" -TimeoutSec 2
        if ($r.status -eq "ok") { $ready = $true; break }
    } catch { }
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 2
}
Write-Host ""
if (-not $ready) {
    Write-Host "The API did not become ready. Logs: docker compose logs api" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "AutoMind AI is running / النظام يعمل:" -ForegroundColor Green
Write-Host "  API + docs        http://localhost:8000/api/v1/docs"
Write-Host "  Admin dashboard   http://localhost:3000"
Write-Host "  ECU simulator     tcp://localhost:35000  (DEMO data)"
Write-Host ""
Write-Host "Create your admin account (two-factor code for an authenticator app is printed):"
Write-Host "  docker compose exec -it api automind create-admin --email you@example.com"
Write-Host ""
Write-Host "Stop:  powershell -ExecutionPolicy Bypass -File scripts\windows\start-local.ps1 -Stop"
